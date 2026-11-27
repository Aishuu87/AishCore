-- Modules/Chat.lua : Tchat. Habille les fenetres de discussion de Blizzard (fond en ombre douce, ombres du texte,
-- arrivee animee des lignes, fondu ligne par ligne) et epure les messages du jeu (butin, argent, XP, reputation,
-- metiers, zones, amis, quetes). Regles anti-taint (Midnight, secret values) : cf. docs/CHAT.md.
--   - les ChatFrames restent le moteur securise : aucun champ ecrit dessus, aucune fonction remplacee, aucun appel
--     ni hook de FCF_* a chaud (le seul FCF_OpenNewWindow, onglet Groupe, est suivi d'un /reload) ;
--   - seules methodes appelees : celles du widget (SetFont, SetFading, ScrollToBottom...), elevees par Blizzard ;
--   - deux hooks (hooksecurefunc) : AddMessage (nos animations) et RefreshDisplay (alpha des lignes au survol) ;
--   - masquage par alpha / texture vide / souris coupee, jamais par reparentage ;
--   - textes secrets (instances) : jamais lus, mesures ni modifies (filtres : passage tel quel).
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local Chat = {}
ns.Modules.Chat = Chat
local L = ns.L

local WHITE = "Interface\\Buttons\\WHITE8x8"
local S = setmetatable({}, { __mode = "k" })   -- etat par ChatFrame (jamais de champ sur leurs frames)
local applied = false                         -- habillage pose au moins une fois (retour arriere : /reload)

local function Secret(v) return ns.IsSecret and ns.IsSecret(v) or false end
local function Cfg() return ns.GetCfg("chat") or {} end
local function On() return Cfg().enabled == true end
Chat.Cfg = Cfg

-- Couleur d'accent : choisie, ou Couleurs Thematiques (cercle de puissance)
local function Accent()
  local c = Cfg()
  local C = ns.Modules and ns.Modules.Colors
  if c.accentThemed ~= false and C and C.Get then
    local t = C.Get("powercircle")
    if t and t[1] then return t[1], t[2], t[3] end
  end
  local a = c.accentColor or { 1, 0.76, 0.25, 1 }
  return a[1], a[2], a[3]
end
Chat.Accent = Accent

local function Hex(r, g, b)
  return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

local function IsCombatLog(cf)
  if _G.COMBATLOG and cf == _G.COMBATLOG then return true end
  if type(_G.IsCombatLog) == "function" then
    local ok, r = pcall(_G.IsCombatLog, cf)
    if ok and r then return true end
  end
  return false
end

-- Toutes les fenetres (permanentes et temporaires : whispers en onglet)
local function ForEachFrame(fn)
  local seen = {}
  for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
    local cf = _G["ChatFrame" .. i]
    if cf and not seen[cf] then seen[cf] = true; fn(cf) end
  end
  for _, name in ipairs(_G.CHAT_FRAMES or {}) do
    local cf = _G[name]
    if cf and not seen[cf] then seen[cf] = true; fn(cf) end
  end
end
Chat.ForEachFrame = ForEachFrame

local function Part(cf, suffix)
  local n = cf.GetName and cf:GetName()
  return n and _G[n .. suffix]
end

-------------------------------------------------------------------------------------------------------------------
-- Habillage
-------------------------------------------------------------------------------------------------------------------
local BG_TEXTURES = { "Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
  "LeftTexture", "RightTexture", "BottomTexture", "TopTexture" }
local GLOBAL_BUTTONS = { "ChatFrameMenuButton", "ChatFrameChannelButton", "QuickJoinToastButton",
  "ChatFrameToggleVoiceDeafenButton", "ChatFrameToggleVoiceMuteButton", "TextToSpeechButtonFrame" }

local function StripTexture(t)
  if t and t.GetObjectType and t:GetObjectType() == "Texture" then t:SetTexture(nil) end
end

-- Coupe la souris d'un cadre et de ses enfants (boutons masques : plus de zone cliquable invisible)
local function MouseTree(f, on, depth)
  if not f or (depth or 0) > 3 then return end
  if f.EnableMouse and not (f.IsForbidden and f:IsForbidden()) then pcall(f.EnableMouse, f, on) end
  if f.GetChildren then
    for _, c in ipairs({ f:GetChildren() }) do MouseTree(c, on, (depth or 0) + 1) end
  end
end

-- Cadres tenus a alpha 0 par le surveillant (Blizzard les refait apparaitre au survol)
local hidden = {}
local function SetHidden(f, on)
  if not f then return end
  if on then
    if not hidden[f] then hidden[f] = true; MouseTree(f, false) end
  elseif hidden[f] then
    hidden[f] = nil
    MouseTree(f, true)
    f:SetAlpha(1)
  end
end

-- Fond en bloc : panneau plein (texture 9 morceaux des Extra Barres). L'ombre douce est dessinee ligne par ligne
-- (UpdateLines), a la maniere de Glass.
local function StyleBackground(cf, st, c)
  local holder = st.bg
  if not holder then
    holder = CreateFrame("Frame", nil, cf)
    holder:SetAllPoints(cf)
    holder:SetFrameLevel(math.max(0, cf:GetFrameLevel()))
    holder:EnableMouse(false)
    holder:SetScript("OnSizeChanged", function() Chat.RefreshBackground(cf) end)
    holder._alpha = 1
    st.bg = holder
  end
  local EB = ns.Modules and ns.Modules.ExtraBars
  local style = c.bgStyle or "shadow"
  local show = On() and style == "solid" and EB and EB.StyleBackground
  if not show then
    if holder.__bg then holder.__bg:Hide() end
    return
  end
  local w, h = cf:GetWidth(), cf:GetHeight()
  if Secret(w) or Secret(h) or not w or w < 1 then return end
  local pad = c.bgPad or 10
  EB.StyleBackground(holder, {
    bgEnabled = true, bgTexture = "solid",
    bgColor = c.bgColor or { 0, 0, 0, 0.55 }, bgPadX = pad, bgPadY = pad, bgEdge = 0,
    bgBorderSize = c.bgBorderSize or 0, bgBorderColor = c.bgBorderColor,
  }, w, h, true)
  if holder.__bg then
    holder.__bg:SetFrameLevel(holder:GetFrameLevel())
    holder.__bg:Show()
  end
end
function Chat.RefreshBackground(cf)
  local st = S[cf]
  if st and st.bg then StyleBackground(cf, st, Cfg()) end
end

-- Onglet : textures retirees, liseré d'accent sous l'onglet actif
local function StyleTab(cf, st, c)
  local tab = Part(cf, "Tab")
  if not tab then return end
  st.tab = tab
  if c.styleTabs == false then return end
  local keep = { [tab.glow or false] = true, [tab.conversationIcon or false] = true }
  for _, r in ipairs({ tab:GetRegions() }) do
    if not keep[r] and r ~= st.tabLine then StripTexture(r) end
  end
  if not st.tabLine then
    local line = tab:CreateTexture(nil, "OVERLAY")
    line:SetTexture(WHITE)
    line:SetHeight(2)
    line:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 8, 2)
    line:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -8, 2)
    line:SetAlpha(0)
    st.tabLine = line
  end
  local fs = tab.Text or Part(tab, "Text")
  if fs and fs.SetFont then
    fs:SetFont(Chat.TabFont(c))
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
  end
end

-- Historique des messages envoyes (fleche haut / bas), garde d'un /reload a l'autre.
-- Navigation a nous (OnArrowPressed) : celle du widget ne repond pas sur le tchat de Blizzard.
-- Aucun champ ni hook de methode sur le cadre de saisie : HookScript (cote C) et table locale.
local HIST_MAX = 50
local histEB = setmetatable({}, { __mode = "k" })   -- eb -> { typed, idx, draft }
local histSession = {}
local function HistoryDB()
  if type(AishaddonDB) ~= "table" then return histSession end
  AishaddonDB.chatHistory = AishaddonDB.chatHistory or {}
  return AishaddonDB.chatHistory
end

local function HistSet(self, h, text)
  self:SetText(text)
  self:SetCursorPosition(#text)
end

-- Texte suivi pendant la saisie ; l'effacement par Blizzard apres l'envoi (non utilisateur) est ignore
local function HistTextChanged(self, userInput)
  local h = histEB[self]
  local t = self:GetText()
  if Secret(t) then h.typed = nil; return end
  if t ~= "" or userInput then h.typed = t end
  if userInput then h.idx = nil end   -- saisie a la main : on repart du bas de l'historique
end

-- Apres l'envoi : ligne gardee (les commandes / aussi, comme Blizzard)
local function HistEnter(self)
  local h = histEB[self]
  local text = h.typed
  h.typed, h.idx, h.draft = nil, nil, nil
  if type(text) ~= "string" or text:match("^%s*$") then return end
  local db = HistoryDB()
  if db[#db] == text then return end
  db[#db + 1] = text
  while #db > HIST_MAX do table.remove(db, 1) end
end

local function HistArrow(self, key)
  if key ~= "UP" and key ~= "DOWN" then return end
  -- liste d'autocompletion des noms ouverte : les fleches sont a elle
  local ac = _G.AutoCompleteBox
  if ac and ac:IsShown() and ac.parent == self then return end
  local h = histEB[self]
  local db = HistoryDB()
  if #db == 0 then return end
  if key == "UP" then
    if not h.idx then
      local cur = self:GetText()
      h.draft = (not Secret(cur)) and cur or ""
      h.idx = #db + 1
    end
    if h.idx > 1 then
      h.idx = h.idx - 1
      HistSet(self, h, db[h.idx])
    end
  elseif h.idx then
    h.idx = h.idx + 1
    if h.idx > #db then
      h.idx = nil
      HistSet(self, h, h.draft or "")
    else
      HistSet(self, h, db[h.idx])
    end
  end
end

local function SetupHistory(eb)
  if eb.SetAltArrowKeyMode then eb:SetAltArrowKeyMode(false) end
  if histEB[eb] then return end
  histEB[eb] = {}
  eb:HookScript("OnTextChanged", HistTextChanged)
  eb:HookScript("OnEnterPressed", HistEnter)
  eb:HookScript("OnArrowPressed", HistArrow)
  -- Blizzard peut remettre le mode Alt a l'ouverture : repose a chaque prise de focus
  eb:HookScript("OnEditFocusGained", function(self)
    local h = histEB[self]
    h.typed, h.idx, h.draft = nil, nil, nil
    if On() and self.SetAltArrowKeyMode then self:SetAltArrowKeyMode(false) end
  end)
end

-- Cadre de saisie : textures de Blizzard retirees, fond sombre et filet d'accent
local function StyleEditBox(cf, st, c)
  local eb = cf.editBox or Part(cf, "EditBox")
  if not eb then return end
  st.eb = eb
  SetupHistory(eb)
  if c.styleEditBox == false then return end
  for _, r in ipairs({ eb:GetRegions() }) do
    if r ~= st.ebLine then StripTexture(r) end
  end
  if not st.ebBg then
    local bg = CreateFrame("Frame", nil, eb, "BackdropTemplate")
    bg:SetPoint("TOPLEFT", eb, "TOPLEFT", 2, -4)
    bg:SetPoint("BOTTOMRIGHT", eb, "BOTTOMRIGHT", -2, 4)
    bg:SetFrameLevel(math.max(0, eb:GetFrameLevel() - 1))
    bg:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
    bg:EnableMouse(false)
    st.ebBg = bg
  end
  local r, g, b = Accent()
  st.ebBg:SetBackdropColor(0, 0, 0, 0.6)
  st.ebBg:SetBackdropBorderColor(r, g, b, 0.55)
  local font = c.font or ns.FONT_FALLBACK
  local _, size = eb:GetFont()
  if size and not Secret(size) then
    eb:SetFont(font, size, "")
    eb:SetShadowOffset(1, -1)
    local header = eb.header or Part(eb, "Header")
    if header and header.SetFont then header:SetFont(font, size, "") end
  end
end

-- Taille enregistree par Blizzard pour la fenetre (jamais relue sur le widget : on la remplace)
local function BlizzardFontSize(cf)
  local id = cf.GetID and cf:GetID()
  if id and GetChatWindowInfo then
    local ok, _, size = pcall(GetChatWindowInfo, id)
    if ok and size and not Secret(size) and size > 0 then return size end
  end
  local _, size = cf:GetFont()
  if Secret(size) then return 14 end
  return size or 14
end

local function WantedFont(cf, c)
  local size = c.fontSizeCustom and (c.fontSize or 14) or BlizzardFontSize(cf)
  local flags = (c.outline and c.outline ~= "NONE") and c.outline or ""
  return c.font or ns.FONT_FALLBACK, size, flags
end

local function ApplyFont(cf, st, c)
  local font, size, flags = WantedFont(cf, c)
  cf:SetFont(font, size, flags)
  st.font, st.size, st.flags = font:lower(), size, flags
  if c.shadow ~= false then
    local o = c.shadowOffset or 1
    cf:SetShadowColor(0, 0, 0, c.shadowAlpha or 0.9)
    cf:SetShadowOffset(o, -o)
  else
    cf:SetShadowOffset(0, 0)
  end
  if cf.SetSpacing then cf:SetSpacing(c.spacing or 2) end
  st.gDirty = true   -- couche des lignes : geometrie et police a refaire
end

-- Reglages du fondu natif, poses seulement s'ils changent : le widget relance son fondu (lignes reaffichees) a
-- chaque appel, et ApplySettings repasse ici a chaque UPDATE_CHAT_WINDOWS -> le tchat se remontrait tout seul.
-- Module actif : le fondu du widget est coupe en permanence et le module fait le sien (UpdateLines / HoldAlphas).
-- Rendre la main au widget relancait son fondu (tout revenait a 100 % puis refondait).
local function ApplyFading(cf, c)
  if not cf.SetFading then return end
  local fading, tv, fd = true, 120, 3   -- valeurs de Blizzard (gabarit des fenetres de discussion)
  if On() then fading = false end
  local st = S[cf] or {}
  if st.fFading ~= fading then cf:SetFading(fading); st.fFading = fading end
  if cf.SetTimeVisible and st.fTv ~= tv then cf:SetTimeVisible(tv); st.fTv = tv end
  if cf.SetFadeDuration and st.fFd ~= fd then cf:SetFadeDuration(fd); st.fFd = fd end
end

-- Boutons propres a une fenetre : copier (survol) et retour en bas (historique remonte)
local function MakeIconButton(cf, icon, tip)
  local b = CreateFrame("Button", nil, cf)
  b:SetSize(18, 18)
  b:SetFrameLevel(cf:GetFrameLevel() + 20)
  local t = b:CreateTexture(nil, "ARTWORK")
  t:SetAllPoints()
  t:SetTexture(icon)
  b.icon = t
  b:SetScript("OnEnter", function(self)
    self.icon:SetVertexColor(1, 1, 1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(tip)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self)
    self.icon:SetVertexColor(0.8, 0.8, 0.8)
    GameTooltip:Hide()
  end)
  t:SetVertexColor(0.8, 0.8, 0.8)
  b:SetAlpha(0)
  b:Hide()
  return b
end

local function StyleButtons(cf, st)
  if not st.copyBtn then
    st.copyBtn = MakeIconButton(cf, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", L["CHAT_COPY_TT"])
    st.copyBtn:SetPoint("TOPRIGHT", cf, "TOPRIGHT", 2, 2)
    st.copyBtn:SetScript("OnClick", function() Chat.ShowCopy(cf) end)
  end
  if not st.jumpBtn then
    st.jumpBtn = MakeIconButton(cf, "Interface\\Buttons\\Arrow-Down-Up", L["CHAT_JUMP_TT"])
    st.jumpBtn:SetSize(20, 20)
    st.jumpBtn:SetPoint("BOTTOMRIGHT", cf, "BOTTOMRIGHT", 2, -2)
    st.jumpBtn:SetScript("OnClick", function() if cf.ScrollToBottom then cf:ScrollToBottom() end end)
  end
end

-------------------------------------------------------------------------------------------------------------------
-- Couche des lignes : ombre douce derriere chaque ligne (a la Glass) et colonne d'horodatage a gauche du texte.
-- Cadre a nous sous le FontStringContainer ; chaque morceau suit l'alpha de sa ligne (fondu natif, arrivee).
-- Heure lue dans l'historique du widget (entry.timestamp, base GetTime) : le message n'est jamais lu.
-------------------------------------------------------------------------------------------------------------------
local TS_GAP = 6
local TS_COLOR = { 0.62, 0.62, 0.62 }
local HOVER_IN, HOVER_OUT = 0.3, 0.9   -- fondu du survol (secondes)
local function Smooth(x)
  x = math.max(0, math.min(1, x))
  return x * x * (3 - 2 * x)
end
Chat._Smooth = Smooth

function Chat.EnsureLayer(cf, st)
  if st.layer then st.layer:Show(); return st.layer end
  local f = CreateFrame("Frame", nil, cf)
  f:SetAllPoints(cf)
  f:SetFrameLevel(math.max(0, cf:GetFrameLevel()))
  f:EnableMouse(false)
  st.layer = f
  st.rows = {}
  return f
end

-- Degrade : SetAlpha n'agit pas sur un degrade (les bouts restaient en bloc pendant le fondu), l'alpha est donc
-- integre aux couleurs du degrade, objets couleur reutilises (pas de dechets a chaque image)
local function SetGrad(t, cA, cB, r, g, b, a1, a2)
  if cA and t.SetGradient then
    cA:SetRGBA(r, g, b, a1)
    cB:SetRGBA(r, g, b, a2)
    if pcall(t.SetGradient, t, "HORIZONTAL", cA, cB) then return end
  end
  if t.SetGradientAlpha then t:SetGradientAlpha("HORIZONTAL", r, g, b, a1, r, g, b, a2) end
end

local function NewRow(st)
  local f = st.layer
  local r = {}
  for _, k in ipairs({ "l", "m", "r" }) do
    local t = f:CreateTexture(nil, "BACKGROUND")
    t:SetColorTexture(1, 1, 1, 1)
    t:Hide()
    r[k] = t
  end
  if CreateColor then r.cA, r.cB, r.cC, r.cD = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0) end
  r.ts = f:CreateFontString(nil, "ARTWORK")
  r.ts:SetJustifyH("RIGHT")
  r.ts:SetWordWrap(false)
  r.ts:Hide()
  return r
end

-- Geometrie des ombres et police de l'horodatage : refaites quand un reglage ou la taille change
-- Ancre d'une ligne d'ombre / d'heure sur sa FontString. Le widget peut recreer ses lignes (police, taille) :
-- l'objet est compare a chaque image et la ligne reancree s'il a change (sinon ancres mortes, tout en haut).
local function AnchorRow(st, row, line)
  local g = st.geo
  if not g then return end
  row.line = line
  row.l:ClearAllPoints()
  row.l:SetPoint("TOPLEFT", line, "TOPLEFT", -g.ext, g.half)
  row.l:SetPoint("BOTTOMLEFT", line, "BOTTOMLEFT", -g.ext, -g.half)
  row.l:SetWidth(g.edgeL)
  row.r:ClearAllPoints()
  row.r:SetPoint("TOPRIGHT", line, "TOPRIGHT", g.pad, g.half)
  row.r:SetPoint("BOTTOMRIGHT", line, "BOTTOMRIGHT", g.pad, -g.half)
  row.r:SetWidth(g.edgeR)
  row.m:ClearAllPoints()
  row.m:SetPoint("TOPLEFT", row.l, "TOPRIGHT")
  row.m:SetPoint("BOTTOMRIGHT", row.r, "BOTTOMLEFT")
  row.ts:ClearAllPoints()
  row.ts:SetPoint("TOPRIGHT", line, "TOPLEFT", -TS_GAP, 0)
end

-- Geometrie et apparence communes (reglage ou taille changes) ; les ancres sont refaites a l'image suivante
local function LayoutRows(cf, st, c, tsOn)
  local w = cf:GetWidth()
  if Secret(w) or not w then return end
  local pad = c.bgPad or 10
  local ext = pad + (tsOn and ((st.tsW or 0) + TS_GAP) or 0)
  local total = w + ext + pad
  local edgeL = math.max(1, math.min(c.bgEdge or 24, total * 0.3))
  st.geo = {
    pad = pad, ext = ext, half = (c.spacing or 2) / 2, edgeL = edgeL,
    edgeR = math.max(1, math.min(250, total * 0.5, total - edgeL - 1)),
  }
  local col = c.bgColor or { 0, 0, 0, 0.55 }
  local cr, cg, cb, ca = col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 0.55
  st.col = { cr, cg, cb, ca }
  for _, row in ipairs(st.rows) do
    row.line = nil
    row.gA = nil
    row.m:SetColorTexture(cr, cg, cb, ca)
    row.ts:SetFont(st.font or ns.FONT_FALLBACK, st.size or 14, st.flags or "")
    row.ts:SetTextColor(TS_COLOR[1], TS_COLOR[2], TS_COLOR[3])
    if c.shadow ~= false then
      local o = c.shadowOffset or 1
      row.ts:SetShadowColor(0, 0, 0, c.shadowAlpha or 0.9)
      row.ts:SetShadowOffset(o, -o)
    else
      row.ts:SetShadowOffset(0, 0)
    end
  end
end

-- Largeur de la colonne : heure type au format choisi, dans la police du tchat
local function MeasureStamp(st, fmt)
  local row = st.rows[1]
  if not row then return 0 end
  row.ts:SetFont(st.font or ns.FONT_FALLBACK, st.size or 14, st.flags or "")
  row.ts:SetText(date(fmt, time({ year = 2000, month = 1, day = 1, hour = 20, min = 58, sec = 58 })))
  local w = row.ts:GetStringWidth()
  row.tsVal = nil
  if Secret(w) or not w then return 40 end
  return math.ceil(w) + 1
end

-------------------------------------------------------------------------------------------------------------------
-- Noms de canaux courts, a l'affichage : "[1. General - Durotar]" -> "[1]", "[Groupe]" -> "[Gr]"...
-- Ni filtre ni chaine globale touchee : le texte de la FontString visible est reecrit (SetText, methode du widget)
-- apres que Blizzard l'a pose ; historique, copie et liens intacts. Texte secret (instance) : laisse tel quel.
-------------------------------------------------------------------------------------------------------------------
local SHORT_TYPES = {
  { "CHAT_PARTY_GET", "PARTY" }, { "CHAT_PARTY_LEADER_GET", "PARTY_LEADER" }, { "CHAT_PARTY_GUIDE_GET", "PARTY_LEADER" },
  { "CHAT_RAID_GET", "RAID" }, { "CHAT_RAID_LEADER_GET", "RAID_LEADER" }, { "CHAT_RAID_WARNING_GET", "RAID_WARNING" },
  { "CHAT_INSTANCE_CHAT_GET", "INSTANCE_CHAT" }, { "CHAT_INSTANCE_CHAT_LEADER_GET", "INSTANCE_CHAT_LEADER" },
  { "CHAT_GUILD_GET", "GUILD" }, { "CHAT_OFFICER_GET", "OFFICER" },
}
local shortMap   -- { { "|h[Groupe]|h", "|h[Gr]|h" }, ... }
local function ShortMap()
  if shortMap then return shortMap end
  shortMap = {}
  for _, e in ipairs(SHORT_TYPES) do
    local g = _G[e[1]]
    local label = type(g) == "string" and g:match("|h%[(.-)%]|h")
    local short = L["CHAT_SHORT_" .. e[2]]
    if label and short and label ~= short then
      shortMap[#shortMap + 1] = { "|h[" .. label .. "]|h", "|h[" .. short .. "]|h" }
    end
  end
  return shortMap
end

local function Shorten(t)
  if type(t) ~= "string" or Secret(t) or not t:find("|Hchannel:", 1, true) then return t end
  -- canaux numerotes : [1. General - Durotar] -> [1]
  t = t:gsub("(|Hchannel:[^|]-|h)%[(%d+)%.[^%]]-%]|h", "%1[%2]|h")
  for _, p in ipairs(ShortMap()) do
    local a, b = t:find(p[1], 1, true)
    if a then t = t:sub(1, a - 1) .. p[2] .. t:sub(b + 1) end
  end
  return t
end
Chat.Shorten = Shorten

local HoldAlphas   -- cf. plus bas (hook de RefreshDisplay)

-- Alpha voulu d'une ligne : fondu natif recalcule (entry.timestamp, base GetTime), releve par le survol
local function LineWant(c, ts, nowG, hA)
  local a = 1
  if ts then
    local el = nowG - ts
    local tVis, tFade = math.max(1, c.fadeAfter or 30), math.max(0.1, c.fadeDuration or 3)
    a = el <= tVis and 1 or math.max(0, 1 - (el - tVis) / tFade)
  end
  if c.revealOnHover ~= false and hA > a then a = hA end
  return a
end

-- Ligne effacee : cachee (comme le fait le widget), pour que ses liens ne restent pas cliquables invisibles
local function SetLineAlpha(st, line, want)
  st.ourHidden = st.ourHidden or setmetatable({}, { __mode = "k" })
  if want <= 0.001 then
    if line:IsShown() then line:Hide(); st.ourHidden[line] = true end
  else
    if st.ourHidden[line] then st.ourHidden[line] = nil; line:Show() end
    local cur = line:GetAlpha()
    if Secret(cur) or math.abs(cur - want) > 0.002 then line:SetAlpha(want) end
  end
end

local function ShowOurHidden(st)
  if not st.ourHidden then return end
  for line in pairs(st.ourHidden) do line:Show() end
  wipe(st.ourHidden)
end
Chat._ShowOurHidden = ShowOurHidden

-- Chaque image : ombre et heure de chaque ligne visible. Renvoie l'alpha de la ligne la plus visible (fondu du panneau)
local function UpdateLines(cf, st, c, bgAlpha)
  local lines = cf.visibleLines
  if type(lines) ~= "table" or not st.layer then return 1 end
  local perLine = c.bgStyle == "shadow"
  local tsOn = c.timestamps == true
  local fmt = c.timestampFormat or "%H:%M"
  -- alpha de la colonne (option "seulement au survol")
  local tsTarget = (tsOn and (not c.timestampHover or st.tsNear)) and 1 or 0
  local tsA = st.tsA or tsTarget
  if tsA ~= tsTarget then
    tsA = tsA + (tsTarget - tsA) * math.min(1, (st.dt or 0.016) * 10)
    if math.abs(tsA - tsTarget) < 0.01 then tsA = tsTarget end
  end
  st.tsA = tsA
  -- Fondu des lignes fait ici (celui du widget est coupe) : alpha = max(fondu natif recalcule, survol), le survol
  -- en fondu (entree / sortie).
  local managed = c.fade ~= false
  local hTarget = st.hover and 1 or 0
  local hLin = st.hoverLin or 0
  if hLin ~= hTarget then
    local dt = st.dt or 0.016
    hLin = hTarget > hLin and math.min(hTarget, hLin + dt / HOVER_IN) or math.max(hTarget, hLin - dt / HOVER_OUT)
  end
  st.hoverLin = hLin
  local hA = Smooth(hLin)   -- courbe douce : la fin du fondu ne tombe plus d'un coup
  st.hoverA = hA
  if not managed and st.ourHidden and next(st.ourHidden) then ShowOurHidden(st) end
  -- lignes manquantes, reglages changes : geometrie refaite
  local n = #lines
  local grew = false
  while #st.rows < n do st.rows[#st.rows + 1] = NewRow(st); grew = true end
  local w = cf:GetWidth()
  if Secret(w) then w = st.gW end
  if grew or st.gDirty or w ~= st.gW or tsOn ~= st.gTs or fmt ~= st.gFmt then
    st.gDirty, st.gW, st.gTs, st.gFmt = false, w, tsOn, fmt
    st.tsW = tsOn and MeasureStamp(st, fmt) or 0
    LayoutRows(cf, st, c, tsOn)
    for _, row in ipairs(st.rows) do row.tsVal = nil end
  end
  local off = cf.GetScrollOffset and cf:GetScrollOffset()
  if Secret(off) or type(off) ~= "number" then off = 0 end
  local hb = cf.historyBuffer
  local getEntry = hb and hb.GetEntryAtIndex
  local now, nowG = time(), GetTime()
  local maxA = 0
  local col = st.col or { 0, 0, 0, 0.55 }
  -- Le widget garde des lignes au-dela du haut de la zone de texte, a alpha 0 : ignorees (sinon le survol les
  -- revelait au-dessus du tchat, sous les onglets)
  local fsc = cf.FontStringContainer
  local top = fsc and fsc.GetTop and fsc:GetTop()
  if Secret(top) or type(top) ~= "number" then top = nil end
  for k, row in ipairs(st.rows) do
    local line = lines[k]
    local a = 0
    local ts
    if line and row.line ~= line then AnchorRow(st, row, line) end
    local inside = line and row.line == line and (line:IsShown() or (st.ourHidden and st.ourHidden[line]))
    if inside and top then
      local lt = line:GetTop()
      if lt and not Secret(lt) and lt > top + 1 then
        inside = false
        if managed then SetLineAlpha(st, line, 0) end   -- ligne au-dela du haut : reste cachee
      end
    end
    if inside then
      local t = line:GetText()
      if Secret(t) or (type(t) == "string" and t ~= "") then
        -- noms de canaux courts (texte reposé par Blizzard a chaque rafraichissement : refait a chaque changement)
        if c.shortChannels ~= false and not Secret(t) and t ~= row.shortOut then
          local short = Shorten(t)
          if short ~= t then line:SetText(short) end
          row.shortOut = short
        end
        if getEntry then
          local ok, e = pcall(getEntry, hb, off + k)
          ts = ok and type(e) == "table" and e.timestamp
          if Secret(ts) or type(ts) ~= "number" then ts = nil end
        end
        -- alpha de la ligne tenu ici (sauf pendant son animation d'arrivee)
        local anim = st.lineAnims and st.lineAnims[line]
        if managed and not (anim and anim.ag:IsPlaying()) then
          local want = LineWant(c, ts, nowG, hA)
          SetLineAlpha(st, line, want)
          a = want   -- alpha voulu (pas relu : le widget peut le reposer entre-temps)
        else
          a = line:GetAlpha()
          if Secret(a) or type(a) ~= "number" then a = 1 end
        end
      end
    end
    if a > maxA then maxA = a end
    -- ombre
    local ba = perLine and a * bgAlpha or 0
    if ba > 0.005 then
      row.m:SetAlpha(ba)
      if not row.gA or math.abs(row.gA - ba) > 0.004 then
        row.gA = ba
        local A = col[4] * ba
        SetGrad(row.l, row.cA, row.cB, col[1], col[2], col[3], 0, A)
        SetGrad(row.r, row.cC, row.cD, col[1], col[2], col[3], A, 0)
      end
      if not row.m:IsShown() then row.l:Show(); row.m:Show(); row.r:Show() end
    elseif row.m:IsShown() then
      row.l:Hide(); row.m:Hide(); row.r:Hide()
      row.gA = nil
    end
    -- heure
    local ta = a * tsA
    local shown = false
    if ta > 0.005 then
      if ts then
        if row.tsVal ~= ts then
          row.tsVal = ts
          row.ts:SetText(date(fmt, now - math.floor(nowG - ts + 0.5)))
        end
        row.ts:SetAlpha(ta)
        shown = true
      end
    end
    if shown ~= row.ts:IsShown() then row.ts:SetShown(shown) end
  end
  return maxA
end

-- Animations : poussee du conteneur de lignes et arrivee de la ligne du bas, jouees a l'envers (decalage -> 0)
local function EnsureAnims(cf, st)
  if st.anim ~= nil then return st.anim end
  st.anim = false
  local fsc = cf.FontStringContainer
  if not (fsc and fsc.CreateAnimationGroup) then return false end
  local ag = fsc:CreateAnimationGroup()
  local tr = ag:CreateAnimation("Translation")
  tr:SetSmoothing("IN")   -- joue a l'envers : depart rapide, arrivee douce
  st.anim = { ag = ag, tr = tr, h = 0 }
  if st.layer then   -- ombres et horodatage suivent la poussee
    st.anim.ag2 = st.layer:CreateAnimationGroup()
    st.anim.tr2 = st.anim.ag2:CreateAnimation("Translation")
    st.anim.tr2:SetSmoothing("IN")
  end
  st.lineAnims = setmetatable({}, { __mode = "k" })
  return st.anim
end

local function LineAnim(st, line)
  local a = st.lineAnims[line]
  if a then return a end
  local ag = line:CreateAnimationGroup()
  local tr = ag:CreateAnimation("Translation")
  tr:SetSmoothing("IN")
  local al = ag:CreateAnimation("Alpha")
  al:SetFromAlpha(1)
  al:SetToAlpha(0)
  al:SetSmoothing("IN")
  -- En fin d'animation, l'alpha revient a celui d'avant l'animation : celui de l'ancienne ligne du bas (0 si elle
  -- avait disparu en fondu), que Blizzard ne repose pas -> la ligne la plus recente restait invisible jusqu'au survol.
  ag:SetScript("OnFinished", function() if On() then line:SetAlpha(1) end end)
  a = { ag = ag, tr = tr, al = al }
  st.lineAnims[line] = a
  return a
end

-- Appele apres chaque AddMessage de Blizzard (hooksecurefunc) : ne lit ni ne touche le message
local function InformIDs()
  local w, b = ChatTypeInfo and ChatTypeInfo.WHISPER_INFORM, ChatTypeInfo and ChatTypeInfo.BN_WHISPER_INFORM
  return w and w.id, b and b.id
end

-- Journal de session pour la copie : toutes les lignes depuis le /reload (le widget n'en garde que maxLines).
-- Message, couleur et heure ; texte secret (instance) ignore, il ne peut pas etre recopie.
local LOG_MAX = 5000
local function LogMessage(st, msg, r, g, b, t)
  if type(msg) ~= "string" or Secret(msg) or msg == "" then return end
  if Secret(r) or Secret(g) or Secret(b) then r, g, b = nil, nil, nil end
  local log = st.log
  if not log then log = {}; st.log = log end
  log[#log + 1] = { m = msg, r = r, g = g, b = b, t = t or time() }
  if #log > LOG_MAX + 500 then
    local keep = {}
    for i = #log - LOG_MAX + 1, #log do keep[#keep + 1] = log[i] end
    st.log = keep
  end
end

-- Amorce : lignes deja presentes dans le widget au moment du hook (messages du chargement)
local function SeedLog(cf, st)
  st.log = {}
  local hb = cf.historyBuffer
  local getEntry = hb and hb.GetEntryAtIndex
  local n = hb and hb.GetNumElements and hb:GetNumElements()
  if not getEntry or Secret(n) or type(n) ~= "number" then return end
  local now, nowG = time(), GetTime()
  for i = n, 1, -1 do   -- index 1 = plus recent
    local ok, e = pcall(getEntry, hb, i)
    if ok and type(e) == "table" then
      local ts = e.timestamp
      local t = (type(ts) == "number" and not Secret(ts)) and (now - math.floor(nowG - ts + 0.5)) or now
      LogMessage(st, e.message, e.r, e.g, e.b, t)
    end
  end
end

local function OnMessage(cf, msg, r, g, b, typeID)
  local st = S[cf]
  if st then LogMessage(st, msg, r, g, b) end
  if not st or not st.skinned or not On() then return end
  -- message envoye par soi (reponse a un contact) : alerte de l'onglet arretee, meme sans l'ouvrir
  local wi, bi = InformIDs()
  if typeID and not Secret(typeID) and (typeID == wi or typeID == bi) then
    st.unread = nil
    st.ackAlert = true
  -- nouveau message dans un onglet non affiche (hors General) : alerte a nous, en plus du drapeau de Blizzard
  elseif cf ~= _G.DEFAULT_CHAT_FRAME and not cf:IsVisible() then
    st.unread = true
  end
  local c = Cfg()
  if not (c.animIn or c.animPush) then return end
  if not cf:IsVisible() then return end
  local off = cf.GetScrollOffset and cf:GetScrollOffset()
  if off and (Secret(off) or off ~= 0) then return end
  local anim = EnsureAnims(cf, st)
  if not anim then return end
  local dur = math.max(0.05, c.animDuration or 0.3)
  if c.animPush ~= false then
    local _, size = cf:GetFont()
    if Secret(size) or not size then size = 14 end
    local h = size + (c.spacing or 2)
    if anim.ag:IsPlaying() then
      local p = anim.tr:GetSmoothProgress() or 0
      if Secret(p) then p = 0 end
      h = h + anim.h * math.max(0, math.min(1, p))
      anim.ag:Stop()
    end
    anim.h = h
    anim.tr:SetOffset(0, -h)
    anim.tr:SetDuration(dur)
    anim.ag:Play(true)
    if anim.ag2 then
      anim.ag2:Stop()
      anim.tr2:SetOffset(0, -h)
      anim.tr2:SetDuration(dur)
      anim.ag2:Play(true)
    end
  end
  if c.animIn ~= false then
    local lines = cf.visibleLines
    local line = type(lines) == "table" and lines[1]
    if line and line.CreateAnimationGroup then
      local a = LineAnim(st, line)
      a.ag:Stop()
      a.tr:SetOffset(-(c.animOffset or 18), 0)
      a.tr:SetDuration(dur)
      a.al:SetDuration(dur)
      a.ag:Play(true)
    end
  end
end

-- Alpha des lignes repose juste apres chaque rafraichissement du widget (hook de RefreshDisplay), avant l'affichage
-- de l'image : le widget, fondu coupe, remet tout en pleine opacite (sinon clignotement).
function HoldAlphas(cf)   -- declaree avant UpdateLines
  local st = S[cf]
  if not (st and st.skinned and On()) then return end
  local c = Cfg()
  if c.fade == false then return end
  local lines = cf.visibleLines
  if type(lines) ~= "table" then return end
  local hA = st.hoverA or 0
  local off = cf.GetScrollOffset and cf:GetScrollOffset()
  if Secret(off) or type(off) ~= "number" then off = 0 end
  local hb = cf.historyBuffer
  local getEntry = hb and hb.GetEntryAtIndex
  local fsc = cf.FontStringContainer
  local top = fsc and fsc.GetTop and fsc:GetTop()
  if Secret(top) or type(top) ~= "number" then top = nil end
  local nowG = GetTime()
  for k, line in ipairs(lines) do
    local anim = st.lineAnims and st.lineAnims[line]
    if not (anim and anim.ag:IsPlaying()) then
      local lt = top and line:GetTop()
      if lt and not Secret(lt) and lt > top + 1 then
        SetLineAlpha(st, line, 0)
      else
        local t = line:GetText()
        if Secret(t) or (type(t) == "string" and t ~= "") then
          local ts
          if getEntry then
            local ok, e = pcall(getEntry, hb, off + k)
            ts = ok and type(e) == "table" and e.timestamp
            if Secret(ts) or type(ts) ~= "number" then ts = nil end
          end
          SetLineAlpha(st, line, LineWant(c, ts, nowG, hA))
        end
      end
    end
  end
end

local function SkinFrame(cf)
  local st = S[cf]
  if not st then st = {}; S[cf] = st end
  local c = Cfg()
  local combat = IsCombatLog(cf)
  if not st.hooked and cf.AddMessage and not combat then
    st.hooked = true
    -- nouvelle fenetre temporaire (chuchotement) habillee apres son premier message : deja non lue si cachee
    if cf.isTemporary and not cf:IsVisible() then
      local n = cf.GetNumMessages and cf:GetNumMessages()
      if n and not Secret(n) and n > 0 then st.unread = true end
    end
    SeedLog(cf, st)
    hooksecurefunc(cf, "AddMessage", OnMessage)
  end
  if not st.refreshHooked and not combat and type(cf.RefreshDisplay) == "function" then
    st.refreshHooked = true
    hooksecurefunc(cf, "RefreshDisplay", HoldAlphas)
  end
  StyleTab(cf, st, c)
  if combat then st.skinned = true; return end
  if c.bgStyle ~= "blizzard" then
    for _, suf in ipairs(BG_TEXTURES) do StripTexture(Part(cf, suf)) end
  end
  StyleBackground(cf, st, c)
  Chat.EnsureLayer(cf, st)
  st.gDirty = true
  StyleEditBox(cf, st, c)
  StyleButtons(cf, st)
  ApplyFont(cf, st, c)
  ApplyFading(cf, c)
  SetHidden(cf.buttonFrame or Part(cf, "ButtonFrame"), c.hideButtons ~= false)
  SetHidden(cf.ScrollToBottomButton, c.hideButtons ~= false)
  SetHidden(cf.ScrollBar, c.hideScrollBar ~= false)
  st.skinned = true
end

function Chat.ApplySettings()
  Chat.UpdateFilters()
  if not On() then
    if not applied then return end
    -- Desactive : nos elements disparaissent, les reglages de Blizzard reviennent (textures : au /reload)
    for f in pairs(hidden) do SetHidden(f, false) end
    ForEachFrame(function(cf)
      local st = S[cf]
      if st then
        if st.bg and st.bg.__bg then st.bg.__bg:Hide() end
        if st.tabLine then st.tabLine:SetAlpha(0) end
        if st.copyBtn then st.copyBtn:Hide() end
        if st.jumpBtn then st.jumpBtn:Hide() end
        if st.ebBg then st.ebBg:Hide() end
        if st.eb and st.ebA then st.eb:SetAlpha(1); st.ebA = nil end
        if st.bg then st.bg:SetAlpha(1) end
        if st.layer then st.layer:Hide() end
        ShowOurHidden(st)
        if st.tab and st.tabA then st.tab:SetAlpha(1); st.tabA = nil end
        if not IsCombatLog(cf) then
          ApplyFading(cf, Cfg())
          if st.skinned then
            local path = ChatFontNormal and ChatFontNormal:GetFont()
            cf:SetFont(path or ns.FONT_FALLBACK, BlizzardFontSize(cf), "")
          end
        end
        st.skinned = false
      end
    end)
    if Chat.LayoutVBar then Chat.LayoutVBar() end
    return
  end
  applied = true
  local c = Cfg()
  -- Horodatage natif de Blizzard (prefixe du message) coupe : le module a sa propre colonne
  local cvGet = (C_CVar and C_CVar.GetCVar) or _G.GetCVar
  local cvSet = (C_CVar and C_CVar.SetCVar) or _G.SetCVar
  if cvGet and cvSet then
    local cur = cvGet("showTimestamps")
    if cur and cur ~= "none" then cvSet("showTimestamps", "none") end
  end
  for _, n in ipairs(GLOBAL_BUTTONS) do SetHidden(_G[n], c.hideButtons ~= false) end
  ForEachFrame(SkinFrame)
  ForEachFrame(function(cf) local st = S[cf]; if st and st.ebBg then st.ebBg:SetShown(c.styleEditBox ~= false) end end)
  if Chat.LayoutVBar then Chat.LayoutVBar() end
end

-------------------------------------------------------------------------------------------------------------------
-- Surveillant : alpha des elements masques, survol (fond, historique), onglet actif, nouvelles fenetres
-------------------------------------------------------------------------------------------------------------------
local function SelectedDocked()
  local dock = _G.GENERAL_CHAT_DOCK
  if dock and _G.FCFDock_GetSelectedWindow then
    local ok, f = pcall(_G.FCFDock_GetSelectedWindow, dock)
    if ok then return f end
  end
  return _G.SELECTED_CHAT_FRAME
end

-------------------------------------------------------------------------------------------------------------------
-- Onglets : police et couleurs des onglets de Blizzard, ou barre verticale a nous, a gauche du dock.
-- Barre verticale : boutons securises (SecureActionButtonTemplate, type "click") qui cliquent l'onglet de Blizzard,
-- lui cache (alpha 0, souris coupee). Selection, menu du clic droit, clignotement : tout reste a Blizzard, aucun FCF_*
-- appele. Boutons proteges : crees, ordonnes et places hors combat seulement (refaits a la sortie du combat).
-------------------------------------------------------------------------------------------------------------------
local function Vertical(c) return c.tabLayout == "vertical" end

local function IsWhisperFrame(cf)
  local t = cf.chatType   -- lecture seule
  if t == "BN_WHISPER" then return "bn" end
  if t == "WHISPER" then return "w" end
  return nil
end

-- Couleur propre d'un chuchotement : joueur (rose) / Battle.net (bleu)
local function WhisperColor(c, wkind)
  if wkind == "bn" then return c.tabColorBN or { 0.3, 0.78, 1, 1 } end
  if wkind then return c.tabColorWhisper or { 1, 0.5, 1, 1 } end
end

-- Couleur de lueur d'une alerte : celle du chuchotement, sinon "Nouveaux messages"
local function AlertColor(c, wkind)
  return WhisperColor(c, wkind) or c.tabColorAlert or { 0.4, 0.8, 1, 1 }
end
Chat.AlertColor = AlertColor

-- Couleur d'un onglet selon son etat (actif, nouveaux messages, chuchotement joueur / Battle.net, survol)
local function TabColor(c, active, alert, wkind, over)
  if active and c.tabActiveAccent then return Accent() end
  local col
  if alert and not active then col = AlertColor(c, wkind)
  elseif active then col = c.tabColorActive or { 1, 0.82, 0, 1 }
  elseif wkind then col = WhisperColor(c, wkind)
  else col = c.tabColorInactive or { 0.65, 0.65, 0.65, 1 } end
  local r, g, b = col[1] or 1, col[2] or 1, col[3] or 1
  if over and not active then r, g, b = r + (1 - r) * 0.35, g + (1 - g) * 0.35, b + (1 - b) * 0.35 end
  return r, g, b
end
Chat.TabColor = TabColor

local function ActiveColor(c)
  if c.tabActiveAccent then return Accent() end
  local a = c.tabColorActive or { 1, 0.82, 0, 1 }
  return a[1] or 1, a[2] or 0.82, a[3] or 0
end
Chat.ActiveColor = ActiveColor

-- Halo de l'onglet actif (forme icones) : lueur carree des boutons d'action, en mode additif, qui "respire"
local ACTIVE_GLOW = "Interface\\Buttons\\UI-ActionButton-Border"
Chat.ACTIVE_GLOW = ACTIVE_GLOW

-- Epaisseur du contour (1 px, 2 px pour l'onglet actif) ; ordre des bords : haut, bas, gauche, droite
local function SetEdgeSize(edges, px)
  for k, e in ipairs(edges) do
    if k <= 2 then e:SetHeight(px) else e:SetWidth(px) end
  end
end
Chat.SetEdgeSize = SetEdgeSize

-- Halo de l'onglet actif : deux couches additives (une seule restait a peine visible), respiration lente
local function ShowActiveGlow(g1, g2, r, g, b, now)
  local a = 0.65 + 0.35 * (0.5 + 0.5 * math.sin(now * 1.6))
  for _, t in ipairs({ g1, g2 }) do
    t:SetVertexColor(r, g, b)
    t:SetAlpha(a)
    if not t:IsShown() then t:Show() end
  end
end
Chat.ShowActiveGlow = ShowActiveGlow

local function TabFont(c)
  return c.tabFont or ns.FONT_FALLBACK, c.tabFontSize or 12, (c.tabOutline and c.tabOutline ~= "NONE") and c.tabOutline or ""
end
Chat.TabFont = TabFont

local function TabText(tab)
  return tab and (tab.Text or Part(tab, "Text"))
end

-- Couleur du texte d'un onglet de Blizzard (Blizzard la repose a chaque changement d'onglet : tenue chaque image)
local function ColorBlizzardTab(cf, st, c, sel)
  local tab = st.tab
  local fs = TabText(tab)
  if not (fs and fs.SetTextColor) then return end
  local active = (cf == sel) or (not cf.isDocked and cf:IsShown())
  local alert = (not active) and Chat.TabAlert(tab, st)
  local r, g, b = TabColor(c, active, alert, IsWhisperFrame(cf), ns.IsFrameMouseOver(tab))
  local cr, cg, cb = fs:GetTextColor()
  if Secret(cr) or not cr or math.abs(cr - r) + math.abs(cg - g) + math.abs(cb - b) > 0.01 then fs:SetTextColor(r, g, b) end
end

local vbar, vSig
local vbtns, vHiddenTabs = {}, {}
local vDocked = {}   -- fenetres de la barre verticale (liste du dock, refaite par LayoutVBar)
local vDirty = false

local function DockedFrames()
  local dock = _G.GENERAL_CHAT_DOCK
  local list = dock and dock.DOCKED_CHAT_FRAMES   -- lecture seule
  local out = {}
  if type(list) == "table" then
    for _, cf in ipairs(list) do out[#out + 1] = cf end
  end
  if #out == 0 and _G.DEFAULT_CHAT_FRAME then out[1] = _G.DEFAULT_CHAT_FRAME end
  return out
end

local function DockSignature(frames)
  local parts = {}
  for i, cf in ipairs(frames) do parts[i] = cf:GetName() or tostring(i) end
  return table.concat(parts, ",")
end

-- Pictogramme d'un onglet : General, Combat, Groupe, chuchotement Battle.net ; sinon les 2 premieres lettres du nom
-- (chuchotement, onglet perso). Nom secret ou illisible : pictogramme de chuchotement.
local TAB_ICONS = {
  general = "Interface\\GossipFrame\\GossipGossipIcon",
  combat  = "Interface\\Icons\\Ability_DualWield",
  group   = "Interface\\Icons\\INV_Misc_GroupNeedMore",
  bn      = "Interface\\FriendsFrame\\Battlenet-Battleneticon",
  whisper = "Interface\\ChatFrame\\UI-ChatWhisperIcon",
}
Chat.TAB_ICONS = TAB_ICONS

local function Initials(label)
  if type(label) ~= "string" or Secret(label) then return nil end
  label = label:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", "")
  if label:find("|K", 1, true) then return nil end   -- nom Battle.net (jeton protege)
  local out, n = {}, 0
  for ch in label:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    if ch:match("%S") then
      n = n + 1
      out[n] = n == 1 and ch:upper() or ch:lower()
      if n == 2 then break end
    end
  end
  if n == 0 then return nil end
  return table.concat(out)
end
Chat.Initials = Initials

-- Chuchotement Battle.net : nom de l'onglet = jeton protege (|K...|k) ; initiales tirees du BattleTag du contact
local function BNInitials(cf)
  local target = cf.chatTarget   -- lecture seule
  if type(target) ~= "string" or Secret(target) then return nil end
  local getID = _G.BNet_GetBNetIDAccount
  local info
  if getID and C_BattleNet and C_BattleNet.GetAccountInfoByID then
    local ok, id = pcall(getID, target)
    if ok and id and not Secret(id) then
      local ok2, i = pcall(C_BattleNet.GetAccountInfoByID, id)
      if ok2 then info = i end
    end
  end
  local tag = info and info.battleTag
  if type(tag) ~= "string" or Secret(tag) then return nil end
  return Initials((tag:gsub("#.*$", "")))
end

local function TabKind(cf)
  if IsCombatLog(cf) then return "combat" end
  local t = cf.chatType   -- lecture seule
  if t == "BN_WHISPER" then return "bn" end
  if t == "WHISPER" then return "whisper" end
  if cf == _G.ChatFrame1 then return "general" end
  local id = cf.GetID and cf:GetID()
  if id and GetChatWindowInfo then
    local ok, name = pcall(GetChatWindowInfo, id)
    if ok and name == L["CHAT_GROUP_TAB_NAME"] then return "group" end
  end
  return "custom"
end

local function NewVButton(i)
  local b = CreateFrame("Button", "AishCoreChatTab" .. i, vbar, "SecureActionButtonTemplate")
  -- Depuis 10.0, un bouton securise doit etre inscrit au clic enfonce ET relache (le declenchement suit
  -- ActionButtonUseKeyDown) ; useOnKeyDown = false : action au relachement seulement
  b:RegisterForClicks("AnyUp", "AnyDown")
  b:SetAttribute("useOnKeyDown", false)
  b:SetAttribute("type", "click")
  -- Visuel sur un cadre enfant non protege : il peut glisser (arrivee depuis le bord de l'ecran) meme en combat,
  -- le bouton securise, lui, ne bouge pas
  local v = CreateFrame("Frame", nil, b)
  v:SetSize(1, 1)
  b.vis = v
  b.bg = v:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.bg:SetColorTexture(0, 0, 0, 1)
  b.border = {}
  for k, pt in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local t = v:CreateTexture(nil, "BORDER")
    t:SetColorTexture(1, 1, 1, 1)
    t:SetPoint(pt[1])
    t:SetPoint(pt[2])
    if k <= 2 then t:SetHeight(1) else t:SetWidth(1) end
    b.border[k] = t
  end
  b.line = v:CreateTexture(nil, "OVERLAY")   -- liseré d'accent (forme texte)
  b.line:SetWidth(2)
  b.line:SetPoint("TOPLEFT", v, "TOPLEFT", 0, -2)
  b.line:SetPoint("BOTTOMLEFT", v, "BOTTOMLEFT", 0, 2)
  b.line:SetColorTexture(1, 1, 1, 1)
  b.aglow = v:CreateTexture(nil, "BACKGROUND", nil, -8)   -- halo de l'onglet actif, deborde autour
  b.aglow:SetTexture(ACTIVE_GLOW)
  b.aglow:SetBlendMode("ADD")
  b.aglow:SetPoint("CENTER")
  b.aglow:Hide()
  b.aglow2 = v:CreateTexture(nil, "BACKGROUND", nil, -7)
  b.aglow2:SetTexture(ACTIVE_GLOW)
  b.aglow2:SetBlendMode("ADD")
  b.aglow2:SetPoint("CENTER")
  b.aglow2:Hide()
  b.icon = v:CreateTexture(nil, "ARTWORK")
  b.icon:SetPoint("TOPLEFT", 3, -3)
  b.icon:SetPoint("BOTTOMRIGHT", -3, 3)
  b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.ini = v:CreateFontString(nil, "OVERLAY")   -- initiales (forme icone)
  b.ini:SetPoint("CENTER", 0, 0)
  b.name = v:CreateFontString(nil, "OVERLAY")  -- nom (forme texte)
  b.name:SetPoint("LEFT", v, "LEFT", 8, 0)
  b.name:SetPoint("RIGHT", v, "RIGHT", -4, 0)
  b.name:SetJustifyH("LEFT")
  b.name:SetWordWrap(false)
  for _, fs in ipairs({ b.ini, b.name }) do
    fs:SetShadowColor(0, 0, 0, 1)
    fs:SetShadowOffset(1, -1)
  end
  -- lueur sur le cote (nouveau message), cote tchat : cadre a part, fixe, visible meme barre cachee
  local gf = CreateFrame("Frame", nil, b)
  gf:SetAllPoints(b)
  gf:SetFrameLevel(v:GetFrameLevel() + 2)
  b.glowF = gf
  b.glow = gf:CreateTexture(nil, "BACKGROUND", nil, -1)
  b.glow:SetColorTexture(1, 1, 1, 1)
  b.glow:SetPoint("TOPLEFT", gf, "TOPRIGHT", 0, 0)
  b.glow:SetPoint("BOTTOMLEFT", gf, "BOTTOMRIGHT", 0, 0)
  b.glow:SetWidth(10)
  b.glow:Hide()
  b.dot = gf:CreateTexture(nil, "OVERLAY")   -- petit repere lumineux au bord
  b.dot:SetColorTexture(1, 1, 1, 1)
  b.dot:SetPoint("TOPRIGHT", gf, "TOPRIGHT", 0, -3)
  b.dot:SetPoint("BOTTOMRIGHT", gf, "BOTTOMRIGHT", 0, 3)
  b.dot:SetWidth(2)
  b.dot:Hide()
  if CreateColor then b.gcA, b.gcB = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0) end
  b:HookScript("OnEnter", function(self)
    local fs = TabText(self.tab)
    local label = fs and fs:GetText()
    if label then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      pcall(GameTooltip.SetText, GameTooltip, label)
      GameTooltip:Show()
    end
  end)
  b:HookScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function ShowBlizzardTabs()
  for tab in pairs(vHiddenTabs) do SetHidden(tab, false) end
  wipe(vHiddenTabs)
  local over = _G.GeneralDockManagerOverflowButton
  if over then SetHidden(over, false) end
end

local function IconStyle(c) return c.tabVStyle ~= "text" end

-- Fond de la barre (cadre a part, non protege, sous les boutons) : texture des Extra Barres (grunge, doux, plein...)
local vbarBg
local function StyleVBarBg(c, w, h)
  local EB = ns.Modules and ns.Modules.ExtraBars
  local tex = c.tabVBarBg or "none"
  if tex == "none" or not (EB and EB.StyleBackground) then
    if vbarBg then vbarBg:Hide() end
    return
  end
  if not vbarBg then
    vbarBg = CreateFrame("Frame", nil, UIParent)
    vbarBg:EnableMouse(false)
  end
  vbarBg:SetFrameStrata(vbar:GetFrameStrata())
  vbarBg:SetFrameLevel(math.max(0, vbar:GetFrameLevel() - 1))
  vbarBg:ClearAllPoints()
  vbarBg:SetAllPoints(vbar)
  local pad = c.tabVBarPad or 6
  EB.StyleBackground(vbarBg, {
    bgEnabled = true, bgTexture = tex, bgColor = c.tabVBarColor or { 0, 0, 0, 0.6 },
    bgPadX = pad, bgPadY = pad, bgEdge = 16,
  }, w, h, true)
  vbarBg:Show()
end
Chat.StyleVBarBg = StyleVBarBg

-- Debord gauche du fond (horodatages) : connu seulement apres le premier LayoutRows
local function VBarExt(c, cf1)
  local st1 = cf1 and S[cf1]
  return (st1 and st1.geo and c.timestamps) and st1.geo.ext or (c.bgPad or 10)
end

-- Construction / placement de la barre : hors combat seulement
function Chat.LayoutVBar()
  if InCombatLockdown() then vDirty = true; return end
  vDirty = false
  local c = Cfg()
  if not (On() and Vertical(c)) then
    if vbar then vbar:Hide() end
    if vbarBg then vbarBg:Hide() end
    ShowBlizzardTabs()
    wipe(vDocked)
    vSig = nil
    return
  end
  local frames = DockedFrames()
  local cf1 = (_G.GENERAL_CHAT_DOCK and _G.GENERAL_CHAT_DOCK.primary) or _G.DEFAULT_CHAT_FRAME
  if not cf1 then return end
  if not vbar then
    vbar = CreateFrame("Frame", "AishCoreChatTabBar", UIParent)
  end
  -- toujours au-dessus du tchat : strata suivante
  local STRATA = { "BACKGROUND", "LOW", "MEDIUM", "HIGH", "DIALOG", "FULLSCREEN", "FULLSCREEN_DIALOG", "TOOLTIP" }
  local cur = cf1:GetFrameStrata()
  local nextStrata = "MEDIUM"
  for k, v in ipairs(STRATA) do if v == cur then nextStrata = STRATA[math.min(#STRATA, k + 1)] end end
  vbar:SetFrameStrata(nextStrata)
  local font, fsize, flags = TabFont(c)
  local icon = IconStyle(c)
  local w, h
  if icon then
    w = math.max(20, math.min(48, c.tabVWidth or 30)); h = w
  else
    w = math.max(40, math.min(200, c.tabVTextWidth or 90)); h = fsize + 10
  end
  local sp = c.tabVSpacing or 4
  local ext = VBarExt(c, cf1)
  vbar.ext = ext
  vbar:ClearAllPoints()
  vbar:SetPoint("TOPRIGHT", cf1, "TOPLEFT", -(ext + 6) + (c.tabVX or 0), c.tabVY or 0)
  vbar:SetSize(w, math.max(1, #frames * (h + sp)))
  -- onglets de Blizzard du dock rendus avant d'etre recaches (le dock peut avoir change)
  ShowBlizzardTabs()
  wipe(vDocked)
  for i, cf in ipairs(frames) do
    vDocked[cf] = true
    local b = vbtns[i] or NewVButton(i)
    vbtns[i] = b
    local tab = Part(cf, "Tab")
    b:SetAttribute("clickbutton", tab)
    b.cf, b.tab = cf, tab
    b.kind = TabKind(cf)
    b:SetSize(w, h)
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", vbar, "TOPLEFT", 0, -(i - 1) * (h + sp))
    b.vis:SetSize(w, h)
    b.ini:SetFont(font, math.floor(w * 0.42 + 0.5), flags)
    b.aglow:SetSize(w * 1.9, h * 1.9)
    b.aglow2:SetSize(w * 1.75, h * 1.75)
    b.name:SetFont(font, fsize, flags)
    b.iconStyle = icon
    b.label, b.shownKey = nil, nil
    for _, t in ipairs(b.border) do t:SetShown(icon) end
    b.line:SetShown(false)
    b:Show()
    if tab then SetHidden(tab, true); vHiddenTabs[tab] = true end
  end
  for i = #frames + 1, #vbtns do
    local b = vbtns[i]
    b:Hide()
    b.cf, b.tab = nil, nil
    b:SetAttribute("clickbutton", nil)
  end
  local over = _G.GeneralDockManagerOverflowButton
  if over then SetHidden(over, true) end
  vbar.n = #frames
  vbar:SetAlpha(1)
  vbar:Show()
  StyleVBarBg(c, w, math.max(1, #frames * (h + sp) - sp))
  vSig = DockSignature(frames)
end

-- Dock change (nouvel onglet, onglet ferme) : barre refaite (hors combat)
local function CheckVBar(c)
  if not (On() and Vertical(c)) then
    if vbar and vbar:IsShown() and not InCombatLockdown() then Chat.LayoutVBar() end
    return
  end
  if vDirty or not vbar or not vbar:IsShown() or DockSignature(DockedFrames()) ~= vSig then Chat.LayoutVBar(); return end
  -- largeur des horodatages calculee apres le reload : barre replacee quand le debord change
  local cf1 = (_G.GENERAL_CHAT_DOCK and _G.GENERAL_CHAT_DOCK.primary) or _G.DEFAULT_CHAT_FRAME
  local ext = VBarExt(c, cf1)
  if not Secret(ext) and ext ~= vbar.ext then Chat.LayoutVBar() end
end

local function VBarOver()
  return vbar and vbar:IsShown() and ns.IsFrameMouseOver(vbar) or false
end

-- Souris dans le rectangle d'un cadre elargi de `tol` (et de `extL` de plus a gauche)
local function NearFrame(f, tol, extL)
  if not (f and f.IsShown and f:IsShown()) then return false end
  local scale = f:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  local l, b, w, h = f:GetRect()
  if Secret(scale) or Secret(cx) or Secret(cy) or Secret(l) or Secret(b) or Secret(w) or Secret(h) then return false end
  if not l or not scale or scale == 0 then return false end
  cx, cy = cx / scale, cy / scale
  tol = tol or 0
  return cx >= l - tol - (extL or 0) and cx <= l + w + tol and cy >= b - tol and cy <= b + h + tol
end
Chat.NearFrame = NearFrame

-- Souris pres de la colonne d'horodatage (bord gauche du tchat, sur sa hauteur)
local function NearLeftColumn(cf, ext, tol)
  if not cf:IsShown() then return false end
  local scale = cf:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  local l, b, _, h = cf:GetRect()
  if Secret(scale) or Secret(cx) or Secret(cy) or Secret(l) or Secret(b) or Secret(h) then return false end
  if not l or not scale or scale == 0 then return false end
  cx, cy = cx / scale, cy / scale
  return cx >= l - ext - tol and cx <= l + tol and cy >= b - tol and cy <= b + h + tol
end
Chat.NearLeftColumn = NearLeftColumn

-- Onglet en alerte : drapeau de Blizzard (lecture seule) ou lueur de l'onglet affichee
local function TabAlert(tab, st)
  if st and st.unread then return true end
  if not tab then return false end
  local glow = tab.glow
  local blizz = tab.alerting or (glow and glow.IsShown and glow:IsShown() and (glow:GetAlpha() or 0) > 0) or false
  -- alerte de Blizzard deja traitee (reponse envoyee) : ignoree jusqu'a ce qu'il l'arrete
  if st and st.ackAlert then
    if not blizz then st.ackAlert = nil end
    return false
  end
  return blizz and true or false
end
Chat.TabAlert = TabAlert

local V_DUR, V_STAGGER = 0.28, 0.05   -- arrivee de chaque onglet, decalage entre onglets (secondes)
local function OutCubicV(x)
  x = math.max(0, math.min(1, x))
  local y = 1 - x
  return 1 - y * y * y
end

-- Chaque image : arrivee en cascade depuis le bord gauche, pictogramme / nom, couleurs, clignotement des alertes
local function UpdateVBar(c, sel, show, elapsed)
  if not (vbar and vbar:IsShown()) then return end
  local n = vbar.n or #vbtns
  local total = V_DUR + math.max(0, n - 1) * V_STAGGER
  local t = vbar._t or total
  if not c.tabsHover then t = total
  elseif show then t = math.min(total, t + elapsed)
  else t = math.max(0, t - elapsed) end
  vbar._t = t
  if vbarBg and vbarBg:IsShown() then vbarBg:SetAlpha(OutCubicV(t / total)) end
  local btnA = c.tabVBtnAlpha or 0.55
  local left = vbar:GetLeft()
  if Secret(left) or not left then left = 0 end
  local now = GetTime()
  local pulse = 0.5 + 0.5 * math.sin(now * 6)
  local ar, ag, ab = Accent()
  for i, b in ipairs(vbtns) do
    local cf, tab = b.cf, b.tab
    if cf and b:IsShown() then
      -- cascade : chaque onglet part du bord de l'ecran, un peu apres le precedent
      local p = OutCubicV((t - (i - 1) * V_STAGGER) / V_DUR)
      local dx = -(left + b.vis:GetWidth() + 16) * (1 - p)
      if b.dx ~= dx then
        b.dx = dx
        b.vis:ClearAllPoints()
        b.vis:SetPoint("TOPLEFT", b, "TOPLEFT", dx, 0)
      end
      b.vis:SetAlpha(p)
      -- pictogramme / initiales ou nom (refaits quand le nom de l'onglet change)
      local fs = TabText(tab)
      local label = fs and fs:GetText()
      local secret = Secret(label)
      if secret or label ~= b.label then
        b.label = (not secret) and label or nil
        if b.iconStyle then
          local kind = b.kind
          local ini
          if kind == "bn" then ini = BNInitials(cf)
          elseif kind == "whisper" or kind == "custom" then ini = Initials(label) end
          if ini then
            b.icon:Hide(); b.ini:SetText(ini); b.ini:Show()
          else
            b.icon:SetTexture(TAB_ICONS[kind] or TAB_ICONS.whisper); b.icon:Show(); b.ini:Hide()
          end
          b.name:Hide()
        else
          b.icon:Hide(); b.ini:Hide()
          b.name:SetText(label or "")
          b.name:Show()
        end
      end
      local active = cf == sel
      local alert = (not active) and TabAlert(tab, S[cf])
      local over = b:IsMouseOver()
      local wk = IsWhisperFrame(cf)
      local r, g, bl = TabColor(c, active, alert, wk, over)
      b.name:SetTextColor(r, g, bl)
      if b.iconStyle then
        -- onglet actif : pas de changement de couleur, contour + halo qui respire dans la couleur "Onglet actif"
        local tr, tg, tb = TabColor(c, false, alert, wk, over or active)
        b.ini:SetTextColor(tr, tg, tb)
        if active then
          local cr, cg, cb = ActiveColor(c)
          for _, e in ipairs(b.border) do e:SetVertexColor(cr, cg, cb, 1) end
          if not b.thick then SetEdgeSize(b.border, 2); b.thick = true end
          ShowActiveGlow(b.aglow, b.aglow2, cr, cg, cb, now)
        else
          local ba = over and 0.8 or (alert and (0.35 + 0.65 * pulse) or 0.35)
          for _, e in ipairs(b.border) do e:SetVertexColor(tr, tg, tb, ba) end
          if b.thick then SetEdgeSize(b.border, 1); b.thick = nil end
          if b.aglow:IsShown() then b.aglow:Hide(); b.aglow2:Hide() end
        end
        b.icon:SetDesaturated(not (active or over or alert))
        b.icon:SetAlpha((active or over or alert) and 1 or 0.6)
        b.bg:SetAlpha(active and math.min(1, btnA + 0.2) or btnA)
      else
        b.ini:SetTextColor(r, g, bl)
        if b.aglow:IsShown() then b.aglow:Hide(); b.aglow2:Hide() end
        b.line:SetShown(active)
        b.line:SetVertexColor(ar, ag, ab, 1)
        b.bg:SetAlpha(active and math.min(1, btnA * 0.8) or (over and btnA * 0.55 or btnA * 0.33))
      end
      -- nouveau message : lueur pulsee sur le cote
      if alert then
        local col = AlertColor(c, IsWhisperFrame(cf))
        SetGrad(b.glow, b.gcA, b.gcB, col[1] or 1, col[2] or 1, col[3] or 1, 0.25 + 0.6 * pulse, 0)
        b.dot:SetVertexColor(col[1] or 1, col[2] or 1, col[3] or 1, 0.5 + 0.5 * pulse)
        if not b.glow:IsShown() then b.glow:Show(); b.dot:Show() end
      elseif b.glow:IsShown() then
        b.glow:Hide(); b.dot:Hide()
      end
    end
  end
end

-- Chaque image : couche des lignes, fondu du panneau avec le texte, onglets (couleurs, survol, barre verticale)
local function EachFrameUpdate(elapsed)
  local c = Cfg()
  local vertical = Vertical(c)
  local sel = SelectedDocked()
  -- onglets "seulement au survol" : visibles a l'approche de leur propre zone (tolerance), pas de tout le tchat
  local dockNear = Chat.tabsNearDock or false
  UpdateVBar(c, sel, (not c.tabsHover) or dockNear, elapsed)
  for cf, st in pairs(S) do
    if st.skinned then
      st.dt = elapsed
      if st.unread and (cf == sel or cf:IsVisible()) then st.unread = nil end
      -- Saisie au repos (style "une saisie par onglet" : Blizzard la laisse affichee a 35 %) : cachee tant qu'on
      -- ne tape pas (Entree l'ouvre), survol compris ; alpha tenu ici (Blizzard le repose)
      local eb = st.eb
      if eb and eb:IsShown() then
        local typing = eb:HasFocus()
        if not typing then
          local t = eb:GetText()
          typing = Secret(t) or (type(t) == "string" and t ~= "")
        end
        local target = typing and 1 or 0
        local a = st.ebA or target
        if a ~= target then
          a = a + (target - a) * math.min(1, elapsed * 10)
          if math.abs(a - target) < 0.01 then a = target end
        end
        st.ebA = a
        local cur = eb:GetAlpha()
        if Secret(cur) or math.abs(cur - a) > 0.005 then eb:SetAlpha(a) end
      end
      if st.layer and cf:IsVisible() then
        local bgA = st.bg and st.bg._alpha or 1
        local maxA = UpdateLines(cf, st, c, bgA)
        -- panneau : suit le fondu des lignes hors survol
        if st.bg then
          local fadeMul = (c.fade ~= false) and math.max(maxA, st.hoverA or 0) or 1
          st.bg:SetAlpha(bgA * fadeMul)
        end
      end
      -- onglets seulement au survol (Blizzard repose leur alpha : tenu ici) ; dock en barre verticale : onglets caches
      local tab = st.tab
      if tab and c.styleTabs ~= false and not (vertical and vDocked[cf]) then ColorBlizzardTab(cf, st, c, sel) end
      if tab and not (vertical and vDocked[cf]) then
        if c.tabsHover then
          -- onglet qui clignote (nouveau message, nouvel onglet de whisper) : reste visible
          local alert = cf ~= sel and Chat.TabAlert(tab, st)
          local over = (cf.isDocked and dockNear) or (not cf.isDocked and st.tabNear) or alert
          local target = over and 1 or 0
          local a = st.tabA or 1
          if a ~= target then
            a = a + (target - a) * math.min(1, elapsed * 10)
            if math.abs(a - target) < 0.01 then a = target end
          end
          st.tabA = a
          local cur = tab:GetAlpha()
          if Secret(cur) or math.abs(cur - a) > 0.001 then tab:SetAlpha(a) end
        elseif st.tabA then
          st.tabA = nil
          tab:SetAlpha(1)
        end
      end
    end
  end
end

-- Survol d'un cadre, rectangle elargi a gauche de `extL` (colonne d'horodatage)
local function OverFrame(f, extL)
  if not extL or extL <= 0 then return ns.IsFrameMouseOver(f) end
  if not f:IsShown() then return false end
  local scale = f:GetEffectiveScale()
  local cx, cy = GetCursorPosition()
  local left, bottom, width, height = f:GetRect()
  if Secret(scale) or Secret(cx) or Secret(cy) or Secret(left) or Secret(bottom) or Secret(width) or Secret(height) then
    return false
  end
  if not left or not scale or scale == 0 then return false end
  cx, cy = cx / scale, cy / scale
  return cx >= left - extL and cx <= left + width and cy >= bottom and cy <= bottom + height
end

local tick, slowTick = 0, 0
local watcher = CreateFrame("Frame")
watcher:SetScript("OnUpdate", function(_, elapsed)
  if not applied then return end
  for f in pairs(hidden) do
    local a = f:GetAlpha()
    if not Secret(a) and a ~= 0 then f:SetAlpha(0) end
  end
  if On() then EachFrameUpdate(elapsed) end
  tick = tick + elapsed
  if tick < 0.05 then return end
  local dt = tick
  tick = 0
  if not On() then return end
  local c = Cfg()
  slowTick = slowTick + dt
  if slowTick > 1 then
    slowTick = 0
    CheckVBar(c)
    ForEachFrame(function(cf)
      local st = S[cf]
      if not (st and st.skinned) then
        SkinFrame(cf)
      elseif not IsCombatLog(cf) then
        -- Blizzard repose sa police (menu de l'onglet, changement de taille) : on reprend la notre
        local font, size, flags = WantedFont(cf, c)
        local cur, csize, cflags = cf:GetFont()
        if not (Secret(cur) or Secret(csize)) and (not cur or cur:lower() ~= font:lower()
          or math.abs((csize or 0) - size) > 0.5 or (cflags or "") ~= flags) then
          ApplyFont(cf, st, c)
        end
      end
    end)
  end
  local sel = SelectedDocked()
  local ar, ag, ab = Accent()
  local vertical = Vertical(c)
  local vOver = VBarOver()
  local now0 = GetTime()
  local hold0 = c.hoverHold or 1.5
  local TOL = 40
  local dockZone = vertical and vbar or _G.GENERAL_CHAT_DOCK
  if dockZone and NearFrame(dockZone, TOL) then Chat.lastTabsNear = now0 end
  Chat.tabsNearDock = Chat.lastTabsNear and (now0 - Chat.lastTabsNear) < hold0 or false
  ForEachFrame(function(cf)
    local st = S[cf]
    if not (st and st.skinned) then return end
    local shown = cf:IsShown()
    local eb = st.eb
    local focus = eb and eb.HasFocus and eb:HasFocus()
    -- zone survolee : fenetre + colonne d'horodatage a gauche, onglet, saisie ; puis delai avant de cacher
    local ext = (c.timestamps and st.geo) and st.geo.ext or 0
    local tabZone = st.tab and not (vertical and vDocked[cf]) and ns.IsFrameMouseOver(st.tab)
    local mouse = shown and (OverFrame(cf, ext) or tabZone or (vertical and vDocked[cf] and vOver)) or false
    local raw = mouse or (shown and focus) or false
    local now = GetTime()
    local hold = c.hoverHold or 1.5
    if raw then st.lastHover = now end
    if mouse then st.lastMouse = now end
    local hover = raw or (shown and st.lastHover and (now - st.lastHover) < hold) or false
    st.hover = hover
    -- souris seule (sans la saisie)
    st.mouseHover = mouse or (shown and st.lastMouse and (now - st.lastMouse) < hold) or false
    -- horodatage "seulement au survol" : souris pres de sa colonne
    if shown and c.timestamps and NearLeftColumn(cf, ext, 25) then st.lastTsNear = now end
    st.tsNear = shown and st.lastTsNear and (now - st.lastTsNear) < hold or false
    -- onglet d'une fenetre detachee : sa propre zone
    if not cf.isDocked and st.tab and NearFrame(st.tab, 30) then st.lastTabNear = now end
    st.tabNear = st.lastTabNear and (now - st.lastTabNear) < hold or false
    -- fond au survol
    if st.bg then
      local target = (c.bgHover and not hover) and 0 or 1
      local a = st.bg._alpha or 1
      if a ~= target then
        a = a + (target - a) * math.min(1, dt * 8)
        if math.abs(a - target) < 0.01 then a = target end
        st.bg._alpha = a
      end
    end
    -- onglet actif
    if st.tabLine then
      local active = (cf == sel) or (not cf.isDocked and shown)
      local tabHover = st.tab and ns.IsFrameMouseOver(st.tab)
      st.tabLine:SetVertexColor(ar, ag, ab, 1)
      st.tabLine:SetAlpha((c.styleTabs == false or (vertical and vDocked[cf])) and 0 or (active and 1 or (tabHover and 0.35 or 0)))
    end
    if st.copyBtn then
      st.copyBtn:SetShown(shown and c.copyButton ~= false)
      st.copyBtn:SetAlpha(hover and 1 or 0)
    end
    if st.jumpBtn then
      local off = cf.GetScrollOffset and cf:GetScrollOffset()
      local up = off and not Secret(off) and off > 0
      st.jumpBtn:SetShown(shown and c.jumpButton ~= false and up and true or false)
      st.jumpBtn:SetAlpha(1)
      if up then st.jumpBtn.icon:SetVertexColor(ar, ag, ab) end
    end
  end)
end)

-------------------------------------------------------------------------------------------------------------------
-- Fenetre de copie (historique d'une fenetre, ou lien web cliquable)
-------------------------------------------------------------------------------------------------------------------
local copyFrame
local function CopyFrame()
  if copyFrame then return copyFrame end
  local f = CreateFrame("Frame", "AishCoreChatCopy", UIParent, "BackdropTemplate")
  f:SetSize(620, 380)
  f:SetPoint("CENTER", 0, 60)
  f:SetFrameStrata("DIALOG")
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:SetClampedToScreen(true)
  f:SetBackdrop({ bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 })
  f:SetBackdropColor(0.04, 0.04, 0.06, 0.95)
  f.title = f:CreateFontString(nil, "OVERLAY")
  f.title:SetFont(ns.FONT_FALLBACK, 12, "")
  f.title:SetPoint("TOPLEFT", 12, -10)
  local close = ns.SharedWidgets and ns.SharedWidgets.CreateCloseButton(f, 20)
  if close then close:SetPoint("TOPRIGHT", -6, -6) end
  local sf = CreateFrame("ScrollFrame", nil, f)
  sf:SetPoint("TOPLEFT", 12, -32)
  sf:SetPoint("BOTTOMRIGHT", -12, 12)
  local eb = CreateFrame("EditBox", nil, sf)
  eb:SetMultiLine(true)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(0)
  if eb.SetMaxBytes then eb:SetMaxBytes(0) end
  eb:SetFont(ns.FONT_FALLBACK, 12, "")
  eb:SetWidth(590)
  eb:SetHeight(330)   -- hauteur de depart : une EditBox multi-ligne de hauteur nulle n'affiche rien
  eb:SetScript("OnEscapePressed", function() f:Hide() end)
  eb:SetScript("OnCursorChanged", function(_, _, y, _, h)
    local top = sf:GetVerticalScroll()
    local bottom = top + sf:GetHeight()
    y = -y
    if y < top then sf:SetVerticalScroll(y) elseif y + h > bottom then sf:SetVerticalScroll(y + h - sf:GetHeight()) end
  end)
  sf:SetScrollChild(eb)
  sf:EnableMouseWheel(true)
  sf:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, eb:GetHeight() - self:GetHeight())
    self:SetVerticalScroll(math.max(0, math.min(max, self:GetVerticalScroll() - delta * 40)))
  end)
  f.sf, f.eb = sf, eb
  f:Hide()
  copyFrame = f
  return f
end

local function OpenCopy(title, text, small, cf)
  local f = CopyFrame()
  -- Meme police que la fenetre de tchat copiee (ombre comprise)
  local font, size, flags
  if cf then font, size, flags = cf:GetFont() end
  if Secret(font) or Secret(size) or not font then font, size, flags = ns.FONT_FALLBACK, 12, "" end
  if not pcall(f.eb.SetFont, f.eb, font, size, flags or "") then f.eb:SetFont(ns.FONT_FALLBACK, 12, "") end
  pcall(f.eb.SetShadowOffset, f.eb, 1, -1)
  pcall(f.eb.SetShadowColor, f.eb, 0, 0, 0, 1)
  if f.eb.SetSpacing then pcall(f.eb.SetSpacing, f.eb, 2) end
  local r, g, b = Accent()
  f:SetBackdropBorderColor(r, g, b, 0.8)
  f.title:SetTextColor(r, g, b)
  f.title:SetText(title)
  f:SetSize(small and 460 or 620, small and 70 or 380)
  f.eb:SetWidth(small and 430 or 590)
  f.eb:SetText(text)
  f:Show()
  f.eb:SetFocus()
  f.eb:HighlightText()
  if small then f.sf:SetVerticalScroll(0) else
    C_Timer.After(0, function() f.sf:SetVerticalScroll(math.max(0, f.eb:GetHeight() - f.sf:GetHeight())) end)
  end
end

-- Ligne du journal mise en forme : heure grise, couleur du message, liens reduits a leur texte (couleur gardee),
-- icones retirees (une EditBox ne les affiche pas proprement). Chaque |r rend la couleur de la ligne.
local function CopyLine(e, fmt)
  local m = e.m:gsub("|T.-|t", ""):gsub("|A.-|a", ""):gsub("|H.-|h(.-)|h", "%1")
  local col = string.format("|cff%02x%02x%02x", math.floor((e.r or 1) * 255 + 0.5),
    math.floor((e.g or 1) * 255 + 0.5), math.floor((e.b or 1) * 255 + 0.5))
  m = m:gsub("|r", "|r" .. col)
  return "|cff808080" .. date(fmt, e.t) .. "|r " .. col .. m .. "|r"
end

function Chat.ShowCopy(cf)
  local st = S[cf]
  if not st then st = {}; S[cf] = st end
  if not st.log then SeedLog(cf, st) end
  local fmt = Cfg().timestampFormat or "%H:%M"
  local out, err = {}, nil
  for _, e in ipairs(st.log) do
    local ok, line = pcall(CopyLine, e, fmt)
    if ok then out[#out + 1] = line else err = err or line end
  end
  -- Journal vide (fenetre jamais hookee) : repli sur les lignes gardees par le widget, sans mise en forme
  if #out == 0 then
    local n = cf.GetNumMessages and cf:GetNumMessages() or 0
    if Secret(n) then n = 0 end
    for i = 1, n do
      local ok, msg = pcall(cf.GetMessageInfo, cf, i)
      if ok and type(msg) == "string" and not Secret(msg) then out[#out + 1] = msg end
    end
  end
  if #out == 0 or err then
    print(string.format("|cff33bbffAishCore|r copie du tchat : journal=%d lignes=%d erreur=%s",
      #st.log, #out, tostring(err)))
  end
  local ok, e2 = pcall(OpenCopy, L["CHAT_COPY_TITLE"], table.concat(out, "\n"), nil, cf)
  if not ok then print("|cff33bbffAishCore|r copie du tchat : " .. tostring(e2)) end
end


-------------------------------------------------------------------------------------------------------------------
-- Messages epures (filtres d'evenements : textes secrets laisses tels quels)
-------------------------------------------------------------------------------------------------------------------
-- Gabarit de Blizzard ("Vous recevez le butin : %s.") -> motif Lua ; ordre des captures (gabarits positionnels %1$s)
local function Compile(fmt, prefix)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local out, order, auto = {}, {}, 0
  local i, n = 1, #fmt
  while i <= n do
    local ch = fmt:sub(i, i)
    if ch == "%" then
      if fmt:sub(i + 1, i + 1) == "%" then
        out[#out + 1] = "%%"; i = i + 2
      else
        local pos, spec, j = fmt:match("^(%d+)%$([sdf])()", i + 1)
        if not pos then
          spec, j = fmt:match("^[%-%d%.]*([sdfi])()", i + 1)
          auto = auto + 1
          pos = auto
        end
        if not spec then
          out[#out + 1] = "%%"; i = i + 1
        else
          out[#out + 1] = spec == "s" and "(.-)" or "([%d%.,]+)"
          order[#order + 1] = tonumber(pos)
          i = j
        end
      end
    else
      out[#out + 1] = ch:find("[%^%$%(%)%.%[%]%*%+%-%?]") and ("%" .. ch) or ch
      i = i + 1
    end
  end
  local pat = "^" .. table.concat(out)
  if not prefix or pat:sub(-4) == "(.-)" then pat = pat .. "$" end
  return { pat = pat, order = order }
end
Chat._Compile = Compile

local function Run(c, msg)
  if not c then return nil end
  local caps = { msg:match(c.pat) }
  if caps[1] == nil then return nil end
  local args = {}
  for k, pos in ipairs(c.order) do args[pos] = caps[k] end
  return args
end

-- Liste de gabarits globaux (compiles une fois, ceux absents du client ignores)
local function Templates(list)
  local out = {}
  for _, e in ipairs(list) do
    local def = type(e) == "table" and e or { e }
    local c = Compile(_G[def[1]], def.prefix)
    if c then
      c.tag = def.tag or def[1]
      out[#out + 1] = c
    end
  end
  return out
end

local function Match(list, msg)
  for _, c in ipairs(list) do
    local a = Run(c, msg)
    if a then return a, c.tag end
  end
end

local function Num(s)
  if type(s) ~= "string" then return tonumber(s) end
  return tonumber((s:gsub("[^%d]", "")))
end

local function Big(n)
  return (BreakUpLargeNumbers and BreakUpLargeNumbers(n)) or tostring(n)
end

-- Couleurs des messages epures
local GREEN, RED, GREY, GOLD, XP, SKILL = "|cff40ff40", "|cffff4d4d", "|cff9d9d9d", "|cffffd100", "|cffb48cff", "|cff71d5ff"

local function Coins(copper)
  local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or _G.GetCoinTextureString
  if f then
    local ok, s = pcall(f, copper)
    if ok and s then return s end
  end
  return (_G.GetMoneyString and GetMoneyString(copper)) or tostring(copper)
end

-- Montant ecrit par le jeu ("45 Or, 50 Argent, 3 Cuivre") -> cuivre
local MONEY_PARTS
local function ParseMoney(s)
  if not MONEY_PARTS then
    MONEY_PARTS = {}
    for _, e in ipairs({ { "GOLD_AMOUNT", 10000 }, { "SILVER_AMOUNT", 100 }, { "COPPER_AMOUNT", 1 } }) do
      local c = Compile(_G[e[1]])
      if c then MONEY_PARTS[#MONEY_PARTS + 1] = { pat = c.pat:sub(2, -2), mult = e[2] } end
    end
  end
  local total = 0
  for _, p in ipairs(MONEY_PARTS) do
    local v = s:match(p.pat)
    if v then total = total + (Num(v) or 0) * p.mult end
  end
  return total
end

local function ItemIcon(link)
  if not Cfg().lootIcons then return "" end
  local id = link:match("item:(%d+)")
  local icon
  if id then
    icon = (C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(tonumber(id))) or (_G.GetItemIcon and GetItemIcon(tonumber(id)))
  else
    id = link:match("currency:(%d+)")
    if id and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
      local info = C_CurrencyInfo.GetCurrencyInfo(tonumber(id))
      icon = info and info.iconFileID
    end
  end
  return icon and ("|T" .. icon .. ":0:0:0:0:64:64:5:59:5:59|t ") or ""
end

local function ItemQuality(link)
  local id = link:match("item:(%d+)")
  if not id then return nil end
  if C_Item and C_Item.GetItemQualityByID then return C_Item.GetItemQualityByID(tonumber(id)) end
  if _G.GetItemInfo then return select(3, GetItemInfo(link)) end
end

local function Count(n)
  n = Num(n)
  return (n and n > 1) and (" " .. GREY .. "x" .. n .. "|r") or ""
end

-- Butin (soi : "+ [objet] x2", autres : "Nom [objet]")
local LOOT_SELF = Templates({
  "LOOT_ITEM_SELF_MULTIPLE", "LOOT_ITEM_PUSHED_SELF_MULTIPLE", "LOOT_ITEM_CREATED_SELF_MULTIPLE",
  "LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE", "LOOT_ITEM_REFUND_MULTIPLE",
  "LOOT_ITEM_SELF", "LOOT_ITEM_PUSHED_SELF", "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_BONUS_ROLL_SELF", "LOOT_ITEM_REFUND",
})
local LOOT_OTHER = Templates({
  "LOOT_ITEM_MULTIPLE", "LOOT_ITEM_PUSHED_MULTIPLE", "LOOT_ITEM_BONUS_ROLL_MULTIPLE",
  "LOOT_ITEM", "LOOT_ITEM_PUSHED", "LOOT_ITEM_BONUS_ROLL",
})
local function CleanLoot(msg)
  local c = Cfg()
  local a = Match(LOOT_SELF, msg)
  if a then
    local link = a[1]
    return GREEN .. "+|r " .. ItemIcon(link) .. link .. Count(a[2])
  end
  a = Match(LOOT_OTHER, msg)
  if a then
    local who, link = a[1], a[2]
    local minQ = c.othersLootQuality or 0
    if minQ > 0 then
      local q = ItemQuality(link)
      if q and q < minQ then return nil, true end
    end
    return GREY .. who .. "|r " .. ItemIcon(link) .. link .. Count(a[3])
  end
end

local MONEY = Templates({ "LOOT_MONEY_SPLIT_GUILD", "YOU_LOOT_MONEY_GUILD", "LOOT_MONEY_SPLIT", "YOU_LOOT_MONEY",
  "ERR_QUEST_REWARD_MONEY_S" })
local function CleanMoney(msg)
  local a = Match(MONEY, msg)
  if not a then return end
  local copper = ParseMoney(a[1] or "")
  if copper <= 0 then return end
  return GREEN .. "+|r" .. Coins(copper)
end

local CURRENCY = Templates({ "CURRENCY_GAINED_MULTIPLE_BONUS", "CURRENCY_GAINED_MULTIPLE", "CURRENCY_GAINED" })
local function CleanCurrency(msg)
  local a = Match(CURRENCY, msg)
  if not a then return end
  return GREEN .. "+|r " .. ItemIcon(a[1]) .. a[1] .. Count(a[2])
end

-- XP : "+1 234 XP (+617)" (bonus de repos entre parentheses)
local XP_NAMED = Templates({ { "COMBATLOG_XPGAIN_FIRSTPERSON", prefix = true } })
local XP_PLAIN = Templates({ { "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED", prefix = true }, "ERR_QUEST_REWARD_EXP_I" })
local function XPLine(xp, rest)
  local bonus = rest and rest:match("%+?([%d%.,]+)")
  bonus = bonus and Num(bonus)
  return XP .. "+" .. Big(xp) .. " " .. (L["CHAT_XP"]) .. "|r" .. ((bonus and bonus > 0) and (" " .. GREY .. "(+" .. Big(bonus) .. ")|r") or "")
end
local function CleanXP(msg)
  local a = Match(XP_NAMED, msg)
  local xp
  if a then xp = Num(a[2]) else
    a = Match(XP_PLAIN, msg)
    xp = a and Num(a[1])
  end
  if not xp then return end
  local rest = msg:match("%((.-)%)")
  return XPLine(xp, rest)
end

-- Reputation : "+250 Faction" / "-250 Faction" ; nouveau rang : "Faction > Honore"
local REP_UP = Templates({
  "FACTION_STANDING_INCREASED_ACH_BONUS", "FACTION_STANDING_INCREASED_DOUBLE_BONUS", "FACTION_STANDING_INCREASED_BONUS",
  "FACTION_STANDING_INCREASED_ACCOUNT_WIDE", "FACTION_STANDING_INCREASED",
  { "FACTION_STANDING_INCREASED_ACCOUNT_WIDE", prefix = true }, { "FACTION_STANDING_INCREASED", prefix = true },
})
local REP_DOWN = Templates({ "FACTION_STANDING_DECREASED_ACCOUNT_WIDE", "FACTION_STANDING_DECREASED",
  { "FACTION_STANDING_DECREASED", prefix = true } })
local REP_GENERIC = Templates({ "FACTION_STANDING_INCREASED_GENERIC", "FACTION_STANDING_DECREASED_GENERIC" })
local REP_CHANGED = Templates({ "FACTION_STANDING_CHANGED_ACCOUNT_WIDE", "FACTION_STANDING_CHANGED" })
local function CleanRep(msg)
  local a = Match(REP_UP, msg)
  if a then return GREEN .. "+" .. Big(Num(a[2]) or 0) .. "|r " .. a[1] end
  a = Match(REP_DOWN, msg)
  if a then return RED .. "-" .. Big(Num(a[2]) or 0) .. "|r " .. a[1] end
  local tag
  a, tag = Match(REP_GENERIC, msg)
  if a then return ((tag or ""):find("DECREASED") and (RED .. "-|r ") or (GREEN .. "+|r ")) .. a[1] end
  a = Match(REP_CHANGED, msg)
  if a then return a[2] .. " " .. GREY .. ">|r " .. GOLD .. a[1] .. "|r" end
end

local SKILL_T = Templates({ "SKILL_RANK_UP" })
local function CleanSkill(msg)
  local a = Match(SKILL_T, msg)
  if a then return SKILL .. a[1] .. "|r " .. GREY .. ">|r " .. GOLD .. (a[2] or "") .. "|r" end
end

local HONOR_T = Templates({ { "COMBATLOG_HONORGAIN", prefix = true }, { "COMBATLOG_HONORGAIN_NO_RANK", prefix = true },
  { "COMBATLOG_HONORAWARD", prefix = true } })
local function CleanHonor(msg)
  local a, tag = Match(HONOR_T, msg)
  if not a then return end
  local pts = (tag == "COMBATLOG_HONORAWARD") and a[1] or a[#a] or a[3] or a[2]
  pts = Num(pts)
  if not pts then return end
  return "|cffff8040+" .. Big(pts) .. " " .. (_G.HONOR or "Honor") .. "|r"
end

-- Messages systeme : amis, quetes, decouvertes, absent / ne pas deranger, recompenses de quete
local FRIEND_ON = Templates({ "ERR_FRIEND_ONLINE_SS" })
local FRIEND_OFF = Templates({ "ERR_FRIEND_OFFLINE_S" })
local QUEST_ACCEPT = Templates({ "ERR_QUEST_ACCEPTED_S" })
local QUEST_DONE = Templates({ "ERR_QUEST_COMPLETE_S" })
local EXPLORED = Templates({ "ERR_ZONE_EXPLORED_XP", "ERR_ZONE_EXPLORED" })
local QUEST_ITEM = Templates({ "ERR_QUEST_REWARD_ITEM_MULT_IS", "ERR_QUEST_REWARD_ITEM_S" })
local AFK_T = Templates({ { "MARKED_AFK_MESSAGE", prefix = true }, "MARKED_AFK", "CLEARED_AFK",
  { "MARKED_DND", prefix = true }, "CLEARED_DND" })
local ICON_QUEST = "|TInterface\\GossipFrame\\AvailableQuestIcon:0|t "
local ICON_DONE = "|TInterface\\RaidFrame\\ReadyCheck-Ready:0|t "
local ICON_MAP = "|TInterface\\Icons\\INV_Misc_Map_01:0:0:0:0:64:64:5:59:5:59|t "

local function CleanSystem(msg)
  local c = Cfg()
  local a, tag
  if c.cleanFriends ~= false then
    a = Match(FRIEND_ON, msg)
    if a then return GREEN .. "+|r |Hplayer:" .. a[1] .. "|h" .. (a[2] or a[1]) .. "|h" end
    a = Match(FRIEND_OFF, msg)
    if a then return GREY .. "- " .. a[1] .. "|r" end
  end
  if c.hideAFK ~= false and Match(AFK_T, msg) then return nil, true end
  if c.cleanQuest ~= false then
    a = Match(QUEST_ACCEPT, msg)
    if a then return ICON_QUEST .. GOLD .. a[1] .. "|r" end
    a = Match(QUEST_DONE, msg)
    if a then return ICON_DONE .. GOLD .. a[1] .. "|r" end
    a, tag = Match(EXPLORED, msg)
    if a then
      local line = ICON_MAP .. GOLD .. a[1] .. "|r"
      if tag == "ERR_ZONE_EXPLORED_XP" and Num(a[2]) then line = line .. " " .. XP .. "+" .. Big(Num(a[2])) .. " " .. L["CHAT_XP"] .. "|r" end
      return line
    end
  end
  if c.cleanLoot ~= false then
    a, tag = Match(QUEST_ITEM, msg)
    if a then
      if tag == "ERR_QUEST_REWARD_ITEM_MULT_IS" then return GREEN .. "+|r " .. ItemIcon(a[2]) .. a[2] .. Count(a[1]) end
      return GREEN .. "+|r " .. ItemIcon(a[1]) .. a[1]
    end
  end
  if c.cleanMoney ~= false then
    local m = CleanMoney(msg)
    if m then return m end
  end
  if c.cleanXP ~= false then
    a = Match(XP_PLAIN, msg)
    if a and Num(a[1]) then return XPLine(Num(a[1])) end
  end
end

-- Filtre generique : rewrite(msg) -> nouveau texte, ou nil, true pour masquer
local function MakeFilter(flag, rewrite)
  return function(_, _, msg, ...)
    if not On() or (flag and Cfg()[flag] == false) then return false end
    if type(msg) ~= "string" or Secret(msg) then return false end
    local ok, out, hide = pcall(rewrite, msg)
    if not ok then return false end
    if hide then return true end
    if out then return false, out, ... end
    return false
  end
end

-- Changements de canal lies a la zone (General, Commerce, Defense...) : remplaces par "Ancienne zone > Nouvelle"
local function ChannelNoticeFilter(_, _, notice, _, _, _, _, _, zoneChannelID, ...)
  if not On() or Cfg().cleanZone == false then return false end
  if Secret(notice) or Secret(zoneChannelID) then return false end
  if (notice == "YOU_CHANGED" or notice == "YOU_JOINED" or notice == "YOU_LEFT")
    and type(zoneChannelID) == "number" and zoneChannelID ~= 0 then
    return true
  end
  return false
end

-- Pose / depose des filtres. Un filtre s'execute dans le code de chat de Blizzard, qui compte ensuite comme
-- celui de l'addon pour la suite du message ("taint") et garde des valeurs par type de message pour la session :
-- en instance, ou les messages sont secrets, ce code echoue ensuite (constate par Glass Forever). D'ou :
--   - filtres poses seulement module actif ET hors instance (retires en entrant, remis en sortant) ;
--   - jamais de filtre sur les canaux des joueurs (dire, groupe, whispers...), secrets en instance.
local FILTERS = {
  { "CHAT_MSG_LOOT", MakeFilter("cleanLoot", CleanLoot) },
  { "CHAT_MSG_MONEY", MakeFilter("cleanMoney", CleanMoney) },
  { "CHAT_MSG_CURRENCY", MakeFilter("cleanCurrency", CleanCurrency) },
  { "CHAT_MSG_COMBAT_XP_GAIN", MakeFilter("cleanXP", CleanXP) },
  { "CHAT_MSG_COMBAT_FACTION_CHANGE", MakeFilter("cleanRep", CleanRep) },
  { "CHAT_MSG_SKILL", MakeFilter("cleanSkill", CleanSkill) },
  { "CHAT_MSG_COMBAT_HONOR_GAIN", MakeFilter("cleanHonor", CleanHonor) },
  { "CHAT_MSG_SYSTEM", MakeFilter(nil, CleanSystem) },
  { "CHAT_MSG_CHANNEL_NOTICE", ChannelNoticeFilter },
}
local filtersOn = false

function Chat.UpdateFilters()
  local util = _G.ChatFrameUtil
  local Add = (util and util.AddMessageEventFilter) or _G.ChatFrame_AddMessageEventFilter
  local Remove = (util and util.RemoveMessageEventFilter) or _G.ChatFrame_RemoveMessageEventFilter
  if not (Add and Remove) then return end
  local want = On() and not (IsInInstance and IsInInstance())
  if want == filtersOn then return end
  for _, f in ipairs(FILTERS) do
    if want then Add(f[1], f[2]) else Remove(f[1], f[2]) end
  end
  filtersOn = want
end

-- Apercu de la page du GUI : messages d'origine -> version epuree (memes fonctions que les filtres)
function Chat.Examples()
  local out = {}
  local function Add(src, clean)
    if type(src) == "string" and clean then out[#out + 1] = { src, clean } end
  end
  local money = (_G.GOLD_AMOUNT and _G.SILVER_AMOUNT and _G.COPPER_AMOUNT)
    and (GOLD_AMOUNT:format(45) .. ", " .. SILVER_AMOUNT:format(50) .. ", " .. COPPER_AMOUNT:format(3))
  if _G.YOU_LOOT_MONEY and money then Add(YOU_LOOT_MONEY:format(money), CleanMoney(YOU_LOOT_MONEY:format(money))) end
  local item = "|cffffffff|Hitem:2589::::::::1:::::::::|h[" .. (L["CHAT_EXAMPLE_ITEM"]) .. "]|h|r"
  if _G.LOOT_ITEM_SELF_MULTIPLE then
    local m = LOOT_ITEM_SELF_MULTIPLE:format(item, 3)
    Add(m, CleanLoot(m))
  end
  if _G.COMBATLOG_XPGAIN_FIRSTPERSON then
    local m = COMBATLOG_XPGAIN_FIRSTPERSON:format(L["CHAT_EXAMPLE_MOB"], 1234)
    Add(m, CleanXP(m))
  end
  if _G.FACTION_STANDING_INCREASED then
    local m = FACTION_STANDING_INCREASED:format(L["CHAT_EXAMPLE_ZONE_A"], 250)
    Add(m, CleanRep(m))
  end
  if type(_G.CHAT_YOU_CHANGED_NOTICE) == "string" then
    local chan = "1. " .. (_G.GENERAL or "General") .. " - " .. L["CHAT_EXAMPLE_ZONE_B"]
    local ok, m = pcall(string.format, CHAT_YOU_CHANGED_NOTICE, 1, chan)
    if not ok then ok, m = pcall(string.format, CHAT_YOU_CHANGED_NOTICE, chan) end
    Add(ok and m or nil,
      GREY .. L["CHAT_EXAMPLE_ZONE_A"] .. "|r " .. GOLD .. ">|r " .. GOLD .. L["CHAT_EXAMPLE_ZONE_B"] .. "|r")
  end
  return out
end

-- Ligne de changement de zone, ecrite dans la fenetre principale
local lastZone
local function ZoneLine(from, to)
  local cf = _G.DEFAULT_CHAT_FRAME
  if not (cf and cf.AddMessage) then return end
  cf:AddMessage(GREY .. from .. "|r " .. GOLD .. ">|r " .. GOLD .. to .. "|r")
end

-------------------------------------------------------------------------------------------------------------------
-- Onglets : groupe (cree une fois puis /reload), whispers en onglet (reglage natif de Blizzard)
-------------------------------------------------------------------------------------------------------------------
Chat.GROUP_TAB_GROUPS = { "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER" }

function Chat.FindGroupTab()
  local want = L["CHAT_GROUP_TAB_NAME"]
  for i = 1, (_G.NUM_CHAT_WINDOWS or 10) do
    local ok, name, _, _, _, _, _, shown, _, docked = pcall(GetChatWindowInfo, i)
    if ok and name == want and (shown or docked) then return _G["ChatFrame" .. i] end
  end
end

local function CallGroup(cf, method, global, ...)
  if cf[method] then return cf[method](cf, ...) end
  local g = _G[global] or (ChatFrameUtil and ChatFrameUtil[method])
  if g then return g(cf, ...) end
end

-- Seul appel FCF_* du module, suivi d'un /reload : Blizzard reconstruit alors la fenetre en contexte securise
function Chat.CreateGroupTab()
  if InCombatLockdown() then
    print("|cff00b0ff[AishCore]|r " .. L["CHAT_GROUP_TAB_COMBAT"])
    return
  end
  if Chat.FindGroupTab() then
    StaticPopup_Show("AISHCORE_CHAT_RELOAD")
    return
  end
  if not _G.FCF_OpenNewWindow then return end
  local cf = FCF_OpenNewWindow(L["CHAT_GROUP_TAB_NAME"], true) or Chat.FindGroupTab()
  if not cf then return end
  CallGroup(cf, "RemoveAllMessageGroups", "ChatFrame_RemoveAllMessageGroups")
  CallGroup(cf, "RemoveAllChannels", "ChatFrame_RemoveAllChannels")
  for _, g in ipairs(Chat.GROUP_TAB_GROUPS) do CallGroup(cf, "AddMessageGroup", "ChatFrame_AddMessageGroup", g) end
  StaticPopup_Show("AISHCORE_CHAT_RELOAD")
end

StaticPopupDialogs["AISHCORE_CHAT_RELOAD"] = {
  text = L["CHAT_RELOAD_TEXT"],
  button1 = _G.RELOADUI or "Reload", button2 = _G.CANCEL or "Cancel",
  OnAccept = function() ReloadUI() end,
  timeout = 0, whileDead = true, hideOnEscape = true,
}

-------------------------------------------------------------------------------------------------------------------
-- Evenements
-------------------------------------------------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("ZONE_CHANGED_NEW_AREA")
ev:RegisterEvent("UPDATE_CHAT_WINDOWS")
ev:RegisterEvent("UPDATE_FLOATING_CHAT_WINDOWS")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "PLAYER_REGEN_ENABLED" then
    if On() then CheckVBar(Cfg()) end
    return
  end
  if event == "PLAYER_ENTERING_WORLD" or event == "ZONE_CHANGED_NEW_AREA" then
    local zone = GetRealZoneText and GetRealZoneText()
    if Secret(zone) then return end
    local silent = event == "PLAYER_ENTERING_WORLD" and (a1 or a2)   -- connexion / reload
    if zone and zone ~= "" then
      if not silent and lastZone and zone ~= lastZone and On() and Cfg().cleanZone ~= false then
        ZoneLine(lastZone, zone)
      end
      lastZone = zone
    end
    Chat.UpdateFilters()
    if event == "PLAYER_ENTERING_WORLD" then C_Timer.After(0.5, Chat.ApplySettings) end
  elseif On() then
    C_Timer.After(0, Chat.ApplySettings)
  end
end)

-- Cible du survol GUI (cf. UI/ModuleHoverOverlay.lua)
function Chat.GetHoverFrame()
  return SelectedDocked() or _G.DEFAULT_CHAT_FRAME
end

-------------------------------------------------------------------------------------------------------------------
-- Apercu du GUI (UI/ChatPage.lua) : faux tchat a nous, aucun cadre de Blizzard. Messages en boucle (discussions et
-- messages epures) avec les reglages du profil : police, ombres, fond, horodatage, arrivee, poussee, onglets.
-- Hors mode test : pleine opacite. Mode test (P:SetTest) : fondu des lignes (delais raccourcis) et effets de survol.
-------------------------------------------------------------------------------------------------------------------
do
  local PV_TAB_H = 22
  local function OutCubic(x)
    x = math.max(0, math.min(1, x))
    local y = 1 - x
    return 1 - y * y * y
  end

  local function Fmt(global, fallback, ...)
    local f = _G[global]
    if type(f) == "string" then
      local ok, out = pcall(string.format, f, ...)
      if ok then return out end
    end
    return string.format(fallback, ...)
  end

  -- Messages de l'apercu : discussions (gabarits de Blizzard) intercalees avec les messages epures du module
  local function Samples()
    local talk = {
      { "CHAT_GUILD_GET", "[Guild] %s: ", "GUILD", "Thalwen", 1 },
      { "CHAT_SAY_GET", "%s says: ", "SAY", "Korgrim", 2 },
      { "CHAT_PARTY_GET", "[Party] %s: ", "PARTY", "Elyra", 3 },
      { "CHAT_WHISPER_GET", "%s whispers: ", "WHISPER", "Brakkus", 4 },
      { "CHAT_GUILD_GET", "[Guild] %s: ", "GUILD", "Elyra", 5 },
    }
    local clean = Chat.Examples()
    local out = {}
    -- canal numerote (Commerce)
    local ch = ChatTypeInfo and ChatTypeInfo.CHANNEL2
    out[1] = { text = "|Hchannel:channel:2|h[2. " .. (_G.TRADE or "Trade") .. " - " .. L["CHAT_EXAMPLE_ZONE_B"] .. "]|h "
      .. Fmt("CHAT_CHANNEL_GET", "%s: ", "[Korgrim]") .. L["CHAT_PREVIEW_MSG2"],
      r = ch and ch.r or 1, g = ch and ch.g or 0.75, b = ch and ch.b or 0.75 }
    local sys = ChatTypeInfo and ChatTypeInfo.SYSTEM
    for i = 1, math.max(#talk, #clean) do
      local t = talk[i]
      if t then
        local info = ChatTypeInfo and ChatTypeInfo[t[3]]
        out[#out + 1] = { text = Fmt(t[1], t[2], "[" .. t[4] .. "]") .. L["CHAT_PREVIEW_MSG" .. t[5]],
          r = info and info.r or 1, g = info and info.g or 1, b = info and info.b or 1 }
      end
      local e = clean[i]
      if e then out[#out + 1] = { text = e[2], r = sys and sys.r or 1, g = sys and sys.g or 1, b = sys and sys.b or 0 } end
    end
    return out
  end

  local function NewPreviewRow(P)
    local row = CreateFrame("Frame", nil, P)
    for _, k in ipairs({ "l", "m", "r" }) do
      local t = row:CreateTexture(nil, "BACKGROUND")
      t:SetColorTexture(1, 1, 1, 1)
      row[k] = t
    end
    if CreateColor then
      row.cA, row.cB, row.cC, row.cD = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0)
    end
    row.fs = row:CreateFontString(nil, "ARTWORK")
    row.fs:SetJustifyH("LEFT")
    row.fs:SetWordWrap(true)
    row.ts = row:CreateFontString(nil, "ARTWORK")
    row.ts:SetJustifyH("RIGHT")
    row.ts:SetWordWrap(false)
    return row
  end

  -- Police, geometrie, couleurs : refaites a chaque changement de reglage
  local function StyleRow(P, row, c)
    local g = P.geo
    local font, size, flags = g.font, g.size, g.flags
    for _, fs in ipairs({ row.fs, row.ts }) do
      fs:SetFont(font, size, flags)
      if c.shadow ~= false then
        local o = c.shadowOffset or 1
        fs:SetShadowColor(0, 0, 0, c.shadowAlpha or 0.9)
        fs:SetShadowOffset(o, -o)
      else
        fs:SetShadowOffset(0, 0)
      end
    end
    row.ts:SetTextColor(TS_COLOR[1], TS_COLOR[2], TS_COLOR[3])
    row.fs:SetWidth(g.textW)
    row.fs:SetText(c.shortChannels ~= false and Shorten(row.msg.text) or row.msg.text)
    row.fs:SetTextColor(row.msg.r, row.msg.g, row.msg.b)
    row.ts:SetText(date(c.timestampFormat or "%H:%M", row.when))
    local h = row.fs:GetStringHeight() or size
    if Secret(h) then h = size end
    row.h = math.ceil(h) + (c.spacing or 2)
    row:SetSize(g.textW, row.h)
    row.l:ClearAllPoints()
    row.l:SetPoint("TOPLEFT", row, "TOPLEFT", -g.textL, 0)
    row.l:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", -g.textL, 0)
    row.l:SetWidth(g.edgeL)
    row.r:ClearAllPoints()
    row.r:SetPoint("TOPRIGHT", row, "TOPRIGHT", g.pad, 0)
    row.r:SetPoint("BOTTOMRIGHT", row, "BOTTOMRIGHT", g.pad, 0)
    row.r:SetWidth(g.edgeR)
    row.m:ClearAllPoints()
    row.m:SetPoint("TOPLEFT", row.l, "TOPRIGHT")
    row.m:SetPoint("BOTTOMRIGHT", row.r, "BOTTOMLEFT")
    local col = g.col
    row.m:SetColorTexture(col[1], col[2], col[3], col[4])
    row.bgA = nil
    row.fsHalf = (c.spacing or 2) / 2
    row.ts:ClearAllPoints()
    row.ts:SetPoint("TOPRIGHT", row, "TOPLEFT", -TS_GAP, -row.fsHalf)
  end

  local function Restyle(P)
    local c = Cfg()
    local w = P:GetWidth()
    if Secret(w) or not w or w < 50 then w = 400 end
    local cf = _G.DEFAULT_CHAT_FRAME or _G.ChatFrame1
    local font, size, flags = c.font or ns.FONT_FALLBACK, 14, (c.outline and c.outline ~= "NONE") and c.outline or ""
    if cf then font, size, flags = WantedFont(cf, c) end
    local pad = c.bgPad or 10
    local tsW = 0
    if c.timestamps then
      P.measure:SetFont(font, size, flags)
      P.measure:SetText(date(c.timestampFormat or "%H:%M", time({ year = 2000, month = 1, day = 1, hour = 20, min = 58, sec = 58 })))
      local mw = P.measure:GetStringWidth()
      if Secret(mw) or not mw then mw = 40 end
      tsW = math.ceil(mw) + 1 + TS_GAP
    end
    local textL = pad + tsW
    local col = c.bgColor or { 0, 0, 0, 0.55 }
    -- onglets : en haut (Blizzard) ou en colonne a gauche (barre verticale)
    local vertical = c.tabLayout == "vertical"
    local tfont, tsize, tflags = Chat.TabFont(c)
    local offL, offT = 0, PV_TAB_H
    local prev
    P.tabBg:SetFrameLevel(P:GetFrameLevel() + 18)
    for i, t in ipairs(P.tabs) do
      t:SetFrameLevel(P:GetFrameLevel() + 20)
      t.fs:SetFont(tfont, tsize, tflags)
      t.fs:SetShadowColor(0, 0, 0, 1)
      t.fs:SetShadowOffset(1, -1)
      t.fs:ClearAllPoints()
      t.line:ClearAllPoints()
      t:ClearAllPoints()
      if vertical then
        local iconStyle = c.tabVStyle ~= "text"
        local tw, th
        if iconStyle then
          -- boutons carres : pictogramme, ou initiales (chuchotement)
          tw = math.max(20, math.min(48, c.tabVWidth or 30)); th = tw
          t.fs:Hide()
          t.ini:SetFont(tfont, math.floor(tw * 0.42 + 0.5), tflags)
          t.aglow:SetSize(tw * 1.9, th * 1.9)
          t.aglow2:SetSize(tw * 1.75, th * 1.75)
          t.ini:SetText(i >= 3 and Chat.Initials(i == 3 and "Brakkus" or "Kaelys") or "")
          t.ini:SetShown(i >= 3)
          t.icon:SetTexture(i == 1 and Chat.TAB_ICONS.general or Chat.TAB_ICONS.combat)
          t.icon:SetShown(i < 3)
          t.line:Hide()
        else
          -- forme texte : nom, liseré d'accent a gauche
          tw = math.max(40, math.min(200, c.tabVTextWidth or 90)); th = tsize + 10
          t.fs:SetPoint("LEFT", t, "LEFT", 8, 0)
          t.fs:SetPoint("RIGHT", t, "RIGHT", -4, 0)
          t.fs:SetJustifyH("LEFT")
          t.fs:Show()
          t.ini:Hide()
          t.icon:Hide()
          t.line:SetWidth(2)
          t.line:SetPoint("TOPLEFT", t, "TOPLEFT", 0, -2)
          t.line:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 0, 2)
        end
        tw = math.min(tw, math.floor(w * 0.4))
        t:SetSize(tw, th)
        t.baseY = -(i - 1) * (th + (c.tabVSpacing or 4)) + (c.tabVY or 0)
        t.baseX = c.tabVX or 0
        t.dx = nil
        t.glow:ClearAllPoints()
        t.glow:SetPoint("TOPLEFT", P, "TOPLEFT", t.baseX + math.min(tw, math.floor(w * 0.4)), t.baseY)
        t.glow:SetSize(10, th)
        t.dot:ClearAllPoints()
        t.dot:SetPoint("TOPRIGHT", t.glow, "TOPLEFT", 0, -3)
        t.dot:SetPoint("BOTTOMRIGHT", t.glow, "BOTTOMLEFT", 0, 3)
        t.dot:SetWidth(2)
        t:SetPoint("TOPLEFT", P, "TOPLEFT", t.baseX, t.baseY)
        t.bg:Show()
        P.tcolW, P.tcolH = tw, -t.baseY + (c.tabVY or 0) + th
        for _, e in ipairs(t.edges) do e:SetShown(iconStyle) end
        t.iconStyle = iconStyle
        offL, offT = tw + 8, 0
      else
        t.glow:Hide(); t.dot:Hide(); t.aglow:Hide(); t.aglow2:Hide()
        t.fs:Show()
        t.ini:Hide()
        t.icon:Hide()
        for _, e in ipairs(t.edges) do e:Hide() end
        t.fs:SetPoint("CENTER")
        t.fs:SetJustifyH("CENTER")
        local tw = t.fs:GetStringWidth()
        t:SetSize((Secret(tw) or not tw) and 80 or (tw + 20), PV_TAB_H)
        if prev then t:SetPoint("LEFT", prev, "RIGHT", 2, 0) else t:SetPoint("TOPLEFT", P, "TOPLEFT", 4, 0) end
        t.line:SetHeight(2)
        t.line:SetPoint("BOTTOMLEFT", t, "BOTTOMLEFT", 8, 2)
        t.line:SetPoint("BOTTOMRIGHT", t, "BOTTOMRIGHT", -8, 2)
        t.bg:Hide()
      end
      prev = t
    end
    P.panel:ClearAllPoints()
    P.panel:SetPoint("TOPLEFT", P, "TOPLEFT", offL, -offT)
    P.panel:SetPoint("BOTTOMRIGHT")
    P.geo = {
      offL = offL, offT = offT, vertical = vertical,
      font = font, size = size, flags = flags, pad = pad, textL = textL, textW = math.max(40, w - offL - textL - pad),
      edgeL = math.max(1, math.min(c.bgEdge or 24, (w - offL) * 0.3)), edgeR = math.max(1, math.min(250, (w - offL) * 0.5)),
      col = { col[1] or 0, col[2] or 0, col[3] or 0, col[4] or 0.55 },
    }
    P.panel:SetColorTexture(P.geo.col[1], P.geo.col[2], P.geo.col[3], P.geo.col[4])
    for _, row in ipairs(P.rows) do StyleRow(P, row, c) end
  end

  local function PushMessage(P, c)
    if #P.samples == 0 then P.samples = Samples() end
    if #P.samples == 0 then return end
    P.next = (P.next % #P.samples) + 1
    local row = table.remove(P.pool) or NewPreviewRow(P)
    row.msg = P.samples[P.next]
    row.when = time()
    row.age = 0
    row:Show()
    StyleRow(P, row, c)
    table.insert(P.rows, 1, row)
    P.pushH = (c.animPush ~= false) and row.h or 0
    P.pushT = 0
  end

  local function Update(P, dt)
    local c = Cfg()
    if not P.geo then Restyle(P) end
    local g = P.geo
    local dur = math.max(0.05, c.animDuration or 0.3)
    P.timer = (P.timer or 0) - dt
    if P.timer <= 0 then
      P.timer = P.test and 2.4 or 1.6
      PushMessage(P, c)
    end
    -- survol (mode test seulement) : meme delai et meme fondu que le vrai tchat
    local now = GetTime()
    local over = P.test and P:IsMouseOver()
    if over then P.lastOver = now end
    local hover = (not P.test) or over or (P.lastOver and now - P.lastOver < (c.hoverHold or 1.5)) or false
    local hT = hover and 1 or 0
    local hLin = P.hLin or 1
    if hLin ~= hT then
      hLin = hT > hLin and math.min(hT, hLin + dt / HOVER_IN) or math.max(hT, hLin - dt / HOVER_OUT)
    end
    P.hLin = hLin
    local hE = Smooth(hLin)
    local fadeOn = P.test and c.fade ~= false
    local reveal = c.fade ~= false and c.revealOnHover ~= false
    local tVis = math.min(math.max(1, c.fadeAfter or 30), 4)
    local tFade = math.min(math.max(0.1, c.fadeDuration or 3), 2)
    local bgA = (P.test and c.bgHover) and hE or 1
    -- zones de proximite (mode test), comme en jeu : onglets et colonne d'horodatage, tolerance autour
    local nearTabs, nearTs = false, false
    if P.test then
      local scale = P:GetEffectiveScale()
      local cx, cy = GetCursorPosition()
      local l, b, w, h = P:GetRect()
      if l and scale and scale > 0 and not (Secret(cx) or Secret(l)) then
        cx, cy = cx / scale - l, cy / scale - b
        local inY = cy >= -10 and cy <= h + 10
        if g.vertical then
          nearTabs = inY and cx >= -10 and cx <= (g.offL or 0) + 30
        else
          nearTabs = cx >= -10 and cx <= w + 10 and cy >= h - PV_TAB_H - 25 and cy <= h + 10
        end
        nearTs = inY and cx >= (g.offL or 0) - 10 and cx <= (g.offL or 0) + g.textL + 25
      end
    end
    local hold = c.hoverHold or 1.5
    if nearTabs then P.lastTabs = now end
    if nearTs then P.lastTs = now end
    local function Ramp(key, on)
      local v = P[key] or 1
      local tgt = on and 1 or 0
      if v ~= tgt then
        v = v + (tgt - v) * math.min(1, dt * 10)
        if math.abs(v - tgt) < 0.01 then v = tgt end
      end
      P[key] = v
      return v
    end
    local tabsShow = (not (P.test and c.tabsHover)) or (P.lastTabs and now - P.lastTabs < hold) or false
    local tsShow = (not (P.test and c.timestampHover)) or (P.lastTs and now - P.lastTs < hold) or false
    local tsA = c.timestamps and Ramp("tsAr", tsShow) or 0
    local tabA = Ramp("tabAr", tabsShow)
    local style = c.bgStyle or "shadow"
    local perLine = style == "shadow"
    -- poussee
    P.pushT = (P.pushT or 0) + dt
    local push = (P.pushH or 0) * (1 - OutCubic(P.pushT / dur))
    local y, maxA = 0, 0
    local top = P:GetHeight() - (g.offT or PV_TAB_H)
    local i = 1
    while i <= #P.rows do
      local row = P.rows[i]
      if y + (row.h or 0) - push > top then   -- ligne qui deborderait sous les onglets
        row:Hide()
        P.pool[#P.pool + 1] = table.remove(P.rows, i)
      else
        row.age = row.age + dt
        local pin = (c.animIn ~= false) and OutCubic(row.age / dur) or 1
        local a = pin
        if fadeOn then
          local native = row.age <= tVis and 1 or math.max(0, 1 - (row.age - tVis) / tFade)
          a = a * (reveal and math.max(native, hE) or native)
        end
        if a > maxA then maxA = a end
        row:SetAlpha(a)
        row:ClearAllPoints()
        row:SetPoint("BOTTOMLEFT", P, "BOTTOMLEFT", (g.offL or 0) + g.textL, y - push)
        row.fs:ClearAllPoints()
        row.fs:SetPoint("TOPLEFT", row, "TOPLEFT", -(c.animOffset or 18) * (1 - pin), -(row.fsHalf or 1))
        if perLine ~= row.m:IsShown() then row.l:SetShown(perLine); row.m:SetShown(perLine); row.r:SetShown(perLine) end
        if perLine and row.bgA ~= bgA then
          row.bgA = bgA
          local col = g.col
          row.m:SetAlpha(bgA)
          SetGrad(row.l, row.cA, row.cB, col[1], col[2], col[3], 0, col[4] * bgA)
          SetGrad(row.r, row.cC, row.cD, col[1], col[2], col[3], col[4] * bgA, 0)
        end
        row.ts:SetShown(tsA > 0.005)
        row.ts:SetAlpha(tsA)
        y = y + row.h
        i = i + 1
      end
    end
    -- panneau : suit le texte en mode test
    P.panel:SetShown(style == "solid")
    P.panel:SetAlpha(bgA * (fadeOn and math.max(maxA, hE) or 1))
    -- onglets : couleurs (le 3e, un chuchotement, recoit un message toutes les quelques secondes)
    local ar, ag, ab = Accent()
    local alertOn = (now % 6) < 4
    local pulse = 0.5 + 0.5 * math.sin(now * 6)
    -- verticale : arrivee en cascade depuis le bord (mode test + onglets au survol), comme en jeu
    local nT = #P.tabs
    local total = 0.28 + (nT - 1) * 0.05
    local vt = P.vt or total
    if not (P.test and c.tabsHover) then vt = total
    elseif tabsShow then vt = math.min(total, vt + dt)
    else vt = math.max(0, vt - dt) end
    P.vt = vt
    local btnA = c.tabVBtnAlpha or 0.55
    -- fond de la barre verticale (texture des Extra Barres)
    local EB = ns.Modules and ns.Modules.ExtraBars
    local barTex = c.tabVBarBg or "none"
    if g.vertical and barTex ~= "none" and EB and EB.StyleBackground and P.tcolW then
      local key = barTex .. (c.tabVBarPad or 6) .. P.tcolW .. P.tcolH .. table.concat(c.tabVBarColor or {}, ",") .. (c.tabVX or 0) .. (c.tabVY or 0)
      if P.barKey ~= key then
        P.barKey = key
        P.tabBg:ClearAllPoints()
        P.tabBg:SetPoint("TOPLEFT", P, "TOPLEFT", c.tabVX or 0, c.tabVY or 0)
        P.tabBg:SetSize(P.tcolW, P.tcolH)
        local pad = c.tabVBarPad or 6
        EB.StyleBackground(P.tabBg, { bgEnabled = true, bgTexture = barTex, bgColor = c.tabVBarColor or { 0, 0, 0, 0.6 },
          bgPadX = pad, bgPadY = pad, bgEdge = 16 }, P.tcolW, P.tcolH, true)
      end
      P.tabBg:Show()
      P.tabBg:SetAlpha(OutCubic(vt / total))
    else
      P.tabBg:Hide()
    end
    for i, t in ipairs(P.tabs) do
      local active = i == 1
      local over = t:IsMouseOver()
      local wk = (i == 3 and "w") or (i == 4 and "bn") or nil
      local alert = (i == 3 and alertOn) or (i == 4 and ((now + 3) % 6) < 4)
      if g.vertical then
        local pp = OutCubic((vt - (i - 1) * 0.05) / 0.28)
        local dx = -(t:GetWidth() + 12) * (1 - pp)
        if t.dx ~= dx then
          t.dx = dx
          t:ClearAllPoints()
          t:SetPoint("TOPLEFT", P, "TOPLEFT", (t.baseX or 0) + dx, t.baseY or 0)
        end
        t:SetAlpha(pp)
        local r, gg, b = TabColor(c, active, alert, wk, over)
        t.fs:SetTextColor(r, gg, b)
        if t.iconStyle then
          local tr, tg, tb = TabColor(c, false, alert, wk, over or active)
          t.ini:SetTextColor(tr, tg, tb)
          if active then
            local cr, cg, cb = Chat.ActiveColor(c)
            for _, e in ipairs(t.edges) do e:SetVertexColor(cr, cg, cb, 1) end
            Chat.SetEdgeSize(t.edges, 2)
            Chat.ShowActiveGlow(t.aglow, t.aglow2, cr, cg, cb, now)
          else
            local ba = over and 0.8 or (alert and (0.35 + 0.65 * pulse) or 0.35)
            for _, e in ipairs(t.edges) do e:SetVertexColor(tr, tg, tb, ba) end
            Chat.SetEdgeSize(t.edges, 1)
            t.aglow:Hide(); t.aglow2:Hide()
          end
          t.icon:SetDesaturated(not (active or over or alert))
          t.icon:SetAlpha((active or over or alert) and 1 or 0.6)
          t.bg:SetAlpha(active and math.min(1, btnA + 0.2) or btnA)
          t.line:Hide()
        else
          t.ini:SetTextColor(r, gg, b)
          t.aglow:Hide(); t.aglow2:Hide()
          t.line:SetShown(active)
          t.line:SetColorTexture(ar, ag, ab, 1)
          t.bg:SetAlpha(active and math.min(1, btnA * 0.8) or (over and btnA * 0.55 or btnA * 0.33))
        end
        if alert then
          local col = AlertColor(c, wk)
          SetGrad(t.glow, t.gcA, t.gcB, col[1] or 1, col[2] or 1, col[3] or 1, 0.25 + 0.6 * pulse, 0)
          t.dot:SetVertexColor(col[1] or 1, col[2] or 1, col[3] or 1, 0.5 + 0.5 * pulse)
          t.glow:Show(); t.dot:Show()
        else
          t.glow:Hide(); t.dot:Hide()
        end
      else
        t:SetAlpha(tabA)
        if c.styleTabs ~= false then
          t.fs:SetTextColor(TabColor(c, active, alert, wk, over))
        elseif active then
          t.fs:SetTextColor(1, 0.82, 0)
        else
          t.fs:SetTextColor(0.85, 0.75, 0.45)
        end
        t.line:SetColorTexture(ar, ag, ab, 1)
        t.line:SetShown(active and c.styleTabs ~= false)
      end
    end
  end

  function Chat.CreatePreview(parent)
    local P = CreateFrame("Frame", nil, parent)
    P.rows, P.pool, P.samples, P.next = {}, {}, {}, 0
    P.panel = P:CreateTexture(nil, "BACKGROUND", nil, -2)
    P.measure = P:CreateFontString(nil, "ARTWORK")
    P.measure:Hide()
    -- onglets factices
    P.tabs = {}
    P.tabBg = CreateFrame("Frame", nil, P)
    P.tabBg:SetFrameLevel(P:GetFrameLevel())
    P.tabBg:Hide()
    for i, label in ipairs({ _G.GENERAL or "General", _G.COMBAT_LOG or "Combat Log", "Brakkus", "Kaelys" }) do
      local t = CreateFrame("Frame", nil, P)
      t.bg = t:CreateTexture(nil, "BACKGROUND")
      t.bg:SetAllPoints()
      t.bg:SetColorTexture(0, 0, 0, 1)
      t.fs = t:CreateFontString(nil, "OVERLAY")
      t.fs:SetFont(ns.FONT_FALLBACK, 11, "")
      t.fs:SetWordWrap(false)
      t.fs:SetText(label)
      t.line = t:CreateTexture(nil, "OVERLAY")
      t.aglow = t:CreateTexture(nil, "BACKGROUND", nil, -8)
      t.aglow:SetTexture(Chat.ACTIVE_GLOW)
      t.aglow:SetBlendMode("ADD")
      t.aglow:SetPoint("CENTER")
      t.aglow:Hide()
      t.aglow2 = t:CreateTexture(nil, "BACKGROUND", nil, -7)
      t.aglow2:SetTexture(Chat.ACTIVE_GLOW)
      t.aglow2:SetBlendMode("ADD")
      t.aglow2:SetPoint("CENTER")
      t.aglow2:Hide()
      t.icon = t:CreateTexture(nil, "ARTWORK")
      t.icon:SetPoint("TOPLEFT", 3, -3)
      t.icon:SetPoint("BOTTOMRIGHT", -3, 3)
      t.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      t.ini = t:CreateFontString(nil, "OVERLAY")
      t.ini:SetPoint("CENTER")
      t.ini:SetShadowColor(0, 0, 0, 1)
      t.ini:SetShadowOffset(1, -1)
      t.glow = P:CreateTexture(nil, "BACKGROUND", nil, -1)   -- sur P : ne glisse pas avec l'onglet
      t.glow:SetColorTexture(1, 1, 1, 1)
      t.glow:Hide()
      t.dot = P:CreateTexture(nil, "OVERLAY")
      t.dot:SetColorTexture(1, 1, 1, 1)
      t.dot:Hide()
      if CreateColor then t.gcA, t.gcB = CreateColor(0, 0, 0, 0), CreateColor(0, 0, 0, 0) end
      t.edges = {}
      for k, pt in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
        local e = t:CreateTexture(nil, "BORDER")
        e:SetColorTexture(1, 1, 1, 1)
        e:SetPoint(pt[1])
        e:SetPoint(pt[2])
        if k <= 2 then e:SetHeight(1) else e:SetWidth(1) end
        t.edges[k] = e
      end
      t:SetFrameLevel(P:GetFrameLevel() + 20)   -- au-dessus des lignes du faux tchat
      P.tabs[i] = t
    end
    P:SetScript("OnUpdate", Update)
    P:SetScript("OnSizeChanged", function() P.geo = nil end)
    P:SetScript("OnShow", function() P.samples = {} end)   -- messages epures refaits (objets en cache entre-temps)
    function P:Refresh() self.geo = nil end
    function P:SetTest(on)
      self.test = on and true or false
      self.hLin, self.lastOver = on and 0 or 1, nil
      self.timer = 0
    end
    return P
  end
end

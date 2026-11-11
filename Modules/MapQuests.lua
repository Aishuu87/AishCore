-- Modules/MapQuests.lua : quetes sur toutes les cartes (QoL). Deux cases en haut a gauche de la carte du monde :
-- "Quetes a rendre" / "Quetes en cours". Cochees, les pastilles ? et ... du journal s'affichent aussi sur les cartes
-- continent / monde, comme le fait le jeu pour la seule quete suivie.
-- Fournisseur et pins PROPRES a l'addon (MapCanvasDataProviderMixin / MapCanvasPinTemplate). Rien de
-- QuestDataProviderMixin, QuestPinTemplate ni POIButton : leurs methodes, appelees depuis l'addon, ecrivent dans des
-- caches partages (QuestCache, EventRegistry...) que le fournisseur du jeu relit ensuite -> son refresh en combat
-- etait teinte (SetPassThroughButtons bloque a l'ouverture de la carte).
-- Position : GetQuestsOnMap de la carte affichee, sinon celle des zones enfants projetee (GetMapRectOnMap).
-- Reglages : ns.DB.comfort.mapQuestsTurnIn / mapQuestsProgress.
local addonName, ns = ...

local MapQuests = {}
ns.Modules.MapQuests = MapQuests

local PIN_TEMPLATE = "AishCore_QuestPinTemplate"   -- AishCore.xml
local provider
local toggles

-- Pin (mixin global : resolu par l'attribut mixin du XML, a l'instanciation). MapCanvasPinMixin vient de
-- Blizzard_MapCanvas (charge a la demande) : ses methodes sont copiees dans HookMap, sans ecraser les notres.
AishCore_QuestPinMixin = {}
local P = AishCore_QuestPinMixin
local function InheritPinBase()
  if P._base or not MapCanvasPinMixin then return end
  for k, v in pairs(MapCanvasPinMixin) do
    if P[k] == nil then P[k] = v end
  end
  P._base = true
end

-- Atlas a sa taille native (comme POIButton_SetAtlas), sinon fichier de repli a la taille donnee
local function SetIcon(tex, atlas, file, size)
  tex:SetTexCoord(0, 1, 0, 1)
  if not (atlas and tex.SetAtlas and tex:SetAtlas(atlas, true)) then
    tex:SetTexture(file)
    tex:SetSize(size, size)
  end
end

function P:OnLoad()
  if self.SetScalingLimits then self:SetScalingLimits(1, 1, 1) end
end

-- Pastille du jeu : rond (UI-QuestPoi-QuestNumber) + "?" (a rendre) ou "..." (en cours) au centre
function P:OnAcquired(questID, complete)
  self.questID = questID
  SetIcon(self.Bg, "UI-QuestPoi-QuestNumber", "Interface\\Minimap\\UI-Minimap-Background", 32)
  if complete then
    SetIcon(self.Icon, "UI-QuestIcon-TurnIn-Normal", "Interface\\GossipFrame\\ActiveQuestIcon", 18)
  else
    SetIcon(self.Icon, "Quest-In-Progress-Icon-yellow", "Interface\\GossipFrame\\IncompleteQuestIcon", 18)
  end
end

function P:OnMouseEnter()
  local qid = self.questID
  if not qid then return end
  GameTooltip:SetOwner(self, "ANCHOR_CURSOR_RIGHT", 5, 2)
  GameTooltip:SetText(C_QuestLog.GetTitleForQuestID(qid) or ("#" .. qid))
  if C_QuestLog.IsComplete(qid) and QUEST_WATCH_QUEST_READY then
    GameTooltip:AddLine(QUEST_WATCH_QUEST_READY, 0.2, 1, 0.2)
  end
  GameTooltip:Show()
end

function P:OnMouseLeave()
  GameTooltip:Hide()
end

-- Clic gauche : super-suivi de la quete (comme le pin du jeu), API C uniquement
function P:OnMouseClickAction(button)
  local qid = self.questID
  if button ~= "LeftButton" or not (qid and C_SuperTrack) then return end
  if C_SuperTrack.GetSuperTrackedQuestID() == qid then
    C_SuperTrack.ClearAllSuperTracked()
  else
    if C_QuestLog.GetQuestWatchType and not C_QuestLog.GetQuestWatchType(qid) and C_QuestLog.AddQuestWatch then
      C_QuestLog.AddQuestWatch(qid)
    end
    C_SuperTrack.SetSuperTrackedQuestID(qid)
  end
  PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
end

-- SetPassThroughButtons est protege en combat (AcquirePin l'appelle) : saute alors, clic droit non relaye
local SetPassThrough
function P:SetPassThroughButtons(...)
  if InCombatLockdown() then return end
  if not SetPassThrough then
    local mt = getmetatable(self)
    SetPassThrough = mt and type(mt.__index) == "table" and mt.__index.SetPassThroughButtons
  end
  if SetPassThrough then SetPassThrough(self, ...) end
end

local function Cfg() return ns.QoLEnabled() and ns.GetCfg("comfort") or {} end

local function Wanted(qid, c)
  if not (C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(qid)) then return false end
  if C_QuestLog.IsWorldQuest and C_QuestLog.IsWorldQuest(qid) then return false end
  if C_QuestLog.IsComplete(qid) then return c.mapQuestsTurnIn == true end
  return c.mapQuestsProgress == true
end

local function Collect(mapID, into)
  local list = C_QuestLog.GetQuestsOnMap(mapID)
  for _, q in ipairs(list or {}) do
    if not q.isMapIndicatorQuest and not into[q.questID] then into[q.questID] = { q.x, q.y } end
  end
end

-- RefreshAllData de notre fournisseur. Hors des cartes de zone, le jeu n'affiche que la quete super-suivie et
-- celle du point de passage : on les exclut pour ne pas les doubler.
local function Refresh(self)
  local map = self:GetMap()
  if not map then return end
  map:RemoveAllPinsByTemplate(PIN_TEMPLATE)
  local c = Cfg()
  if not (c.mapQuestsTurnIn or c.mapQuestsProgress) then return end
  if InCombatLockdown() then return end
  if GetCVarBool and not GetCVarBool("questPOI") then return end
  local mapID = map:GetMapID()
  local info = mapID and C_Map.GetMapInfo(mapID)
  if not info then return end
  local mt = info.mapType
  if mt ~= Enum.UIMapType.Continent and mt ~= Enum.UIMapType.World and mt ~= Enum.UIMapType.Cosmic then return end

  local shown = {}
  local st = C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID()
  if st then shown[st] = true end
  local focused = QuestMapFrame_GetFocusedQuestID and QuestMapFrame_GetFocusedQuestID()
  if focused then shown[focused] = true end

  -- Positions : carte affichee d'abord, puis zones enfants ramenees dans son repere
  local pos = {}
  Collect(mapID, pos)
  local children = C_Map.GetMapChildrenInfo(mapID, Enum.UIMapType.Zone, true)
  for _, child in ipairs(children or {}) do
    local sub = {}
    Collect(child.mapID, sub)
    if next(sub) then
      local l, r, t, b = C_Map.GetMapRectOnMap(child.mapID, mapID)
      if l and r > l and b > t then
        for qid, p in pairs(sub) do
          if not pos[qid] then pos[qid] = { l + p[1] * (r - l), t + p[2] * (b - t) } end
        end
      end
    end
  end

  local n = 0
  for qid, p in pairs(pos) do
    if not shown[qid] and p[1] >= 0 and p[1] <= 1 and p[2] >= 0 and p[2] <= 1 and Wanted(qid, c) then
      n = n + 1
      local pin = map:AcquirePin(PIN_TEMPLATE, qid, C_QuestLog.IsComplete(qid))
      pin:UseFrameLevelType("PIN_FRAME_LEVEL_ACTIVE_QUEST", n)
      pin:SetPosition(p[1], p[2])
    end
  end
end

local function RefreshAll()
  local map = provider and provider:GetMap()
  if map and map:IsShown() then pcall(Refresh, provider) end
end

-- Cases a cocher (style de la case "auto accept." de Comfort.lua)
local function UpdateToggles()
  if not toggles then return end
  local c = Cfg()
  local CLR = ns.Modules and ns.Modules.Colors
  local col = (CLR and CLR.Get and CLR.Get("powerdotsa")) or { 0.776, 0.710, 0.471, 1 }
  for _, b in ipairs(toggles.boxes) do
    b.fill:SetColorTexture(col[1], col[2], col[3], 1)
    b.fill:SetShown(c[b.key] == true)
  end
  toggles:SetShown(ns.QoLEnabled())
end

local function MakeBox(parent, key, text)
  local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
  b:SetSize(14, 14)
  b:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
  b:SetBackdropColor(0, 0, 0, 0.6)
  b:SetBackdropBorderColor(0.776, 0.710, 0.471, 0.8)
  b.key = key
  b.fill = b:CreateTexture(nil, "ARTWORK")
  b.fill:SetPoint("TOPLEFT", 2, -2)
  b.fill:SetPoint("BOTTOMRIGHT", -2, 2)
  b.label = b:CreateFontString(nil, "OVERLAY")
  b.label:SetFont(ns.FONT_FALLBACK, 12, "OUTLINE")
  b.label:SetPoint("LEFT", b, "RIGHT", 5, 0)
  b.label:SetTextColor(1, 0.82, 0, 1)
  b.label:SetText(text)
  b:SetHitRectInsets(0, -(b.label:GetStringWidth() + 6), 0, 0)
  b:SetScript("OnClick", function(self)
    local c = ns.GetCfg("comfort")
    if not c then return end
    c[self.key] = not c[self.key]
    PlaySound(c[self.key] and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
    UpdateToggles()
    RefreshAll()
  end)
  return b
end

local function EnsureToggles(wm)
  if toggles then return end
  local L = ns.L
  local anchor = wm.ScrollContainer or wm
  toggles = CreateFrame("Frame", nil, anchor)
  toggles:SetSize(150, 36)
  toggles:SetPoint("TOPLEFT", anchor, "TOPLEFT", 12, -46)
  toggles:SetFrameLevel(anchor:GetFrameLevel() + 1500)
  local b1 = MakeBox(toggles, "mapQuestsTurnIn", L["MAPQUESTS_TURNIN"])
  b1:SetPoint("TOPLEFT", 0, 0)
  local b2 = MakeBox(toggles, "mapQuestsProgress", L["MAPQUESTS_PROGRESS"])
  b2:SetPoint("TOPLEFT", b1, "BOTTOMLEFT", 0, -6)
  toggles.boxes = { b1, b2 }
  toggles:SetScript("OnShow", UpdateToggles)
  UpdateToggles()
end

local function HookMap()
  local wm = _G.WorldMapFrame
  if not (wm and wm.AddDataProvider and MapCanvasDataProviderMixin and MapCanvasPinMixin and CreateFromMixins) then
    return false
  end
  if not provider then
    InheritPinBase()
    provider = CreateFromMixins(MapCanvasDataProviderMixin)
    provider.RemoveAllData = function(self)
      local map = self:GetMap()
      if map then map:RemoveAllPinsByTemplate(PIN_TEMPLATE) end
    end
    provider.RefreshAllData = function(self) pcall(Refresh, self) end
    wm:AddDataProvider(provider)
  end
  EnsureToggles(wm)
  return true
end

function MapQuests.ApplySettings()
  if not HookMap() then return end
  UpdateToggles()
  RefreshAll()
end

-- Evenements sur un frame a nous (pas RegisterEvent du fournisseur : il ecrit dans la table d'evenements de la carte)
local pending
local function QueueRefresh()
  if pending then return end
  pending = true
  C_Timer.After(0.2, function() pending = nil; RefreshAll() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("QUEST_LOG_UPDATE")
ev:RegisterEvent("QUEST_WATCH_LIST_CHANGED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(ev.RegisterEvent, ev, "SUPER_TRACKING_CHANGED")
ev:SetScript("OnEvent", function(_, event, name)
  if event == "PLAYER_LOGIN" or (event == "ADDON_LOADED" and name == "Blizzard_WorldMap") then
    HookMap()
  elseif event ~= "ADDON_LOADED" then
    QueueRefresh()
  end
end)

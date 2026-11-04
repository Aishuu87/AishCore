-- Modules/StealthMode.lua : "Mode furtif" -- assombrit l'ecran (vignettage) tant que le joueur est en furtivite
-- (Camouflage, Disparition, Danse de l'ombre, Subterfuge, Rodeur... cf. ns.IsPlayerStealthed dans Colors.lua).
-- Un grand vignettage noir : une texture radiale (Media/UI/Vignette1..5.tga, du plus doux au plus net) etiree a la taille
-- de l'ecran -- donc aussi en ultra large -- plus quatre aplats noirs qui couvrent ce que la texture ne couvre pas quand
-- elle est reduite. Fondu d'entree / de sortie et reglages dans la page "Mode furtif" (EXTRAS).
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local StealthMode = {}
ns.Modules.StealthMode = StealthMode

local TEX_DIR = "Interface\\AddOns\\AishCore\\Media\\UI\\Vignette"
local BIG = 6000   -- debord des aplats (pixels, bien au-dela de n'importe quel ecran)

local frame, tex
local fillers = {}
local p, target = 0, 0      -- progression du fondu (0 = invisible, 1 = plein) et cible
local preview = false       -- apercu pendant que la page de reglages est ouverte

local function Cfg()
  return ns.GetCfg("stealthMode") or {}
end

local function Ease(v)
  if v < 0 then v = 0 elseif v > 1 then v = 1 end
  return v * v * (3 - 2 * v)
end

-- Taille / texture selon les reglages. Largeur et hauteur suivent l'ecran (UIParent) : l'ellipse s'etire d'elle-meme
-- en ultra large. taille 100 % = ellipse inscrite dans l'ecran ; ratio = hauteur de l'ellipse relativement a sa largeur.
-- A l'apparition, le ratio part de RATIO_START (ellipse tres haute, donc vignettage ouvert) et rejoint la valeur reglee
-- pendant le fondu d'entree. entryP = avancement de l'entree : il suit le fondu a la montee et reste fige a la descente
-- (la sortie ne rejoue pas l'animation a l'envers).
local RATIO_START = 2
local entryP = 1

local function LayoutSize()
  if not tex then return end
  local cfg = Cfg()
  local W, H = UIParent:GetWidth(), UIParent:GetHeight()
  local size  = math.max(0.3, math.min(3, tonumber(cfg.size) or 1))
  local ratio = math.max(0.3, math.min(2, tonumber(cfg.ratio) or 1))
  ratio = RATIO_START + (ratio - RATIO_START) * Ease(entryP)
  tex:SetSize(W * size, H * size * ratio)
end

local function Layout()
  if not frame then return end
  local cfg = Cfg()
  local level = math.max(1, math.min(5, math.floor((tonumber(cfg.feather) or 3) + 0.5)))
  tex:SetTexture(TEX_DIR .. level .. ".tga")
  tex:ClearAllPoints()
  tex:SetPoint("CENTER", frame, "CENTER", 0, 0)
  LayoutSize()
  -- Couleur du vignettage (noir par defaut) : texture blanche teintee + aplats de la meme couleur. L'opacite reste celle
  -- de l'assombrissement (alpha du cadre), donc l'alpha du selecteur n'intervient pas.
  local c = cfg.color or { 0, 0, 0, 1 }
  tex:SetVertexColor(c[1], c[2], c[3], 1)
  for _, f in ipairs(fillers) do f:SetColorTexture(c[1], c[2], c[3], 1) end
end

local function ApplyAlpha()
  if not frame then return end
  local cfg = Cfg()
  frame:SetAlpha((tonumber(cfg.darkness) or 0.6) * Ease(p))
end

local driver = CreateFrame("Frame")
local function Step(_, el)
  local cfg = Cfg()
  if target > p then
    p = math.min(target, p + el / math.max(0.05, tonumber(cfg.fadeIn) or 0.6))
  else
    p = math.max(target, p - el / math.max(0.05, tonumber(cfg.fadeOut) or 0.8))
  end
  ApplyAlpha()
  if target == 1 then entryP = p; LayoutSize() end
  if p == target then
    driver:SetScript("OnUpdate", nil)
    if p == 0 and frame then frame:Hide() end
  end
end

local function Ensure()
  if frame then return end
  frame = CreateFrame("Frame", "AishCoreStealthVignette", UIParent)
  frame:SetAllPoints(UIParent)
  frame:SetFrameStrata("BACKGROUND")   -- sous toute l'interface : n'assombrit que le monde
  frame:EnableMouse(false)
  frame:Hide()
  tex = frame:CreateTexture(nil, "BACKGROUND")
  -- Aplats noirs autour de la texture : quand elle est plus petite que l'ecran, ils prennent le relais (les coins de la
  -- texture sont deja opaques, il suffit de les prolonger vers l'exterieur)
  local function Fill(pA, rA, xA, yA, pB, rB, xB, yB)
    local t = frame:CreateTexture(nil, "BACKGROUND")
    t:SetColorTexture(0, 0, 0, 1)
    t:SetPoint(pA, tex, rA, xA, yA)
    t:SetPoint(pB, tex, rB, xB, yB)
    fillers[#fillers + 1] = t
  end
  Fill("BOTTOMLEFT", "TOPLEFT",    -BIG, 0, "TOPRIGHT",    "TOPRIGHT",    BIG, BIG)    -- au-dessus (pleine largeur)
  Fill("TOPLEFT",    "BOTTOMLEFT", -BIG, 0, "BOTTOMRIGHT", "BOTTOMRIGHT", BIG, -BIG)   -- au-dessous (pleine largeur)
  Fill("TOPRIGHT",   "TOPLEFT",    0,    0, "BOTTOMLEFT", "BOTTOMLEFT", -BIG, 0)      -- a gauche
  Fill("TOPLEFT",    "TOPRIGHT",   0,    0, "BOTTOMRIGHT","BOTTOMRIGHT", BIG, 0)      -- a droite
  Layout()
end

-- Doit-on assombrir maintenant ?
local lastWeak = false   -- derniere detection uniquement par la barre "bonus" (a confirmer, cf. Update)

local function Wanted()
  local cfg = Cfg()
  if cfg.enabled ~= true then return false end
  if preview then return true end
  if cfg.disableInCombat == true and (InCombatLockdown() or UnitAffectingCombat("player")) then return false end
  if not ns.IsPlayerStealthed then return false end
  local st, weak = ns.IsPlayerStealthed()
  lastWeak = weak and true or false
  return st and true or false
end

local confirmPending = false

function StealthMode.Update()
  local want = Wanted()
  -- Entree : confirmee apres un court delai (cf. Colors.lua). Sur monture, la barre d'action change un instant avant
  -- IsMounted(), ce qui allumait le vignettage a tort ; une vraie furtivite, elle, tient.
  if want and target == 0 and not preview and lastWeak then
    if not confirmPending then
      confirmPending = true
      C_Timer.After(0.4, function()
        confirmPending = false
        if Wanted() then target = 1; StealthMode.Update() end
      end)
    end
    return
  end
  if want then Ensure() end
  target = want and 1 or 0
  if not frame then return end
  if target == 1 and not frame:IsShown() then entryP = 0; LayoutSize(); ApplyAlpha(); frame:Show() end
  if p ~= target then driver:SetScript("OnUpdate", Step) else ApplyAlpha() end
end

-- ═══ Visibilite en furtivite ═══════════════════════════════════════════════════════════════════
-- Une colonne par element (stealthMode.vis[elem]), cases cumulables : l'une suffit a montrer l'element. Tant que le
-- joueur est furtif (hors combat), une colonne avec au moins une case cochee remplace les regles de visibilite de
-- l'element ; sans case cochee, rien ne change. "Toujours" prime sur les autres.
StealthMode.VIS_ELEMS = { "player", "target", "circle", "priority" }
StealthMode.VIS_KEYS  = { "always", "contested", "friendly", "attackable", "pvp", "instance", "group" }

local stealthed = false   -- furtivite confirmee (la detection "faible" attend 0,4 s, cf. Update)

--- Joueur furtif (etat confirme, independant du vignettage)
function StealthMode.IsStealthed() return stealthed end

-- Zone contestee : tout sauf une zone sure (zone de repos etendue, sanctuaire)
local function InContestedZone()
  if ns.IsRestArea and ns.IsRestArea() then return false end
  local pvp = GetZonePVPInfo and GetZonePVPInfo()
  return pvp ~= "sanctuary"
end

--- nil : pas de regle de furtivite (regles habituelles de l'element) ; sinon true / false.
function ns.StealthVisOverride(elem)
  if not stealthed then return nil end
  local cfg = Cfg()
  if cfg.enabled ~= true then return nil end
  local r = cfg.vis and cfg.vis[elem]
  if not r then return nil end
  local any = false
  for _, k in ipairs(StealthMode.VIS_KEYS) do if r[k] then any = true; break end end
  if not any then return nil end
  if UnitAffectingCombat("player") then return nil end
  if r.always then return true end
  if r.contested and InContestedZone() then return true end
  local hasTarget = UnitExists("target") and not UnitIsDeadOrGhost("target")
  if r.attackable and hasTarget and UnitCanAttack("player", "target") then return true end
  if r.friendly and hasTarget and not UnitCanAttack("player", "target") and UnitIsFriend("player", "target") then return true end
  local inInst, instType = IsInInstance()
  if r.pvp and inInst and (instType == "pvp" or instType == "arena") then return true end
  if r.instance and inInst and (instType == "party" or instType == "raid" or instType == "scenario") then return true end
  if r.group and IsInGroup() then return true end
  return false
end

-- Reevalue la visibilite des 4 elements
function StealthMode.RefreshVisibility()
  local M = ns.Modules
  if M.UnitBars and M.UnitBars.UpdateAllVisibility then M.UnitBars.UpdateAllVisibility() end
  if M.ResourceCircle and M.ResourceCircle.UpdateVisibility then M.ResourceCircle.UpdateVisibility() end
  if M.PriorityBar and M.PriorityBar.UpdateVisibility then M.PriorityBar.UpdateVisibility() end
end

local function SetStealthed(v)
  if v == stealthed then return end
  stealthed = v
  if ns.CallbackRegistry then ns.CallbackRegistry:Trigger("StealthMode.Changed", v) end
  StealthMode.RefreshVisibility()
end

local stPending = false
local function TrackStealth()
  local st, weak = false, false
  if ns.IsPlayerStealthed then st, weak = ns.IsPlayerStealthed() end
  if not st then SetStealthed(false); return end
  if not weak then SetStealthed(true); return end
  -- Detection faible (barre "bonus" du Voleur) : confirmee apres un court delai, comme le vignettage
  if stealthed or stPending then return end
  stPending = true
  C_Timer.After(0.4, function()
    stPending = false
    if ns.IsPlayerStealthed and ns.IsPlayerStealthed() then SetStealthed(true) end
  end)
end

function StealthMode.ApplySettings()
  if frame then Layout() end
  StealthMode.Update()
  StealthMode.RefreshVisibility()
end

-- Apercu pendant l'ouverture de la page de reglages
function StealthMode.SetPreview(on)
  preview = on and true or false
  StealthMode.Update()
end

-- Seuls le Voleur et le Druide ont une furtivite de classe : ailleurs le module reste en sommeil (aucun evenement,
-- donc aucun appel a chaque UNIT_AURA). L'apercu de la page de reglages fonctionne toujours (SetPreview).
local _, PLAYER_CLASS = UnitClass("player")
if PLAYER_CLASS ~= "ROGUE" and PLAYER_CLASS ~= "DRUID" then return end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("UPDATE_STEALTH")
ev:RegisterEvent("UPDATE_BONUS_ACTIONBAR")   -- Voleur : la barre "bonus" suit la furtivite (Danse de l'ombre, Subterfuge)
ev:RegisterEvent("PLAYER_REGEN_DISABLED")    -- option "Desactive en combat"
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
if PLAYER_CLASS == "ROGUE" then
  ev:RegisterUnitEvent("UNIT_POWER_FREQUENT", "player")   -- rattrapage, comme les animations d'orbes
end
ev:RegisterEvent("DISPLAY_SIZE_CHANGED")
ev:RegisterEvent("UI_SCALE_CHANGED")
ev:RegisterUnitEvent("UNIT_AURA", "player")
-- Conditions de la visibilite en furtivite
local VIS_EVENTS = { PLAYER_TARGET_CHANGED = true, GROUP_ROSTER_UPDATE = true, ZONE_CHANGED = true,
  ZONE_CHANGED_INDOORS = true, ZONE_CHANGED_NEW_AREA = true, PLAYER_UPDATE_RESTING = true }
for e in pairs(VIS_EVENTS) do ev:RegisterEvent(e) end
ev:SetScript("OnEvent", function(_, event)
  if event == "DISPLAY_SIZE_CHANGED" or event == "UI_SCALE_CHANGED" then
    if frame then Layout() end
    return
  end
  if VIS_EVENTS[event] or event == "PLAYER_REGEN_ENABLED" then
    if stealthed then C_Timer.After(0, StealthMode.RefreshVisibility) end
    if VIS_EVENTS[event] then return end
  end
  TrackStealth()
  StealthMode.Update()
end)

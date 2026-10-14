-- Modules/WellFedCircle.lua : Cercle Bien Nourri
-- Visible uniquement pendant qu'on mange : le cercle se vide sur la duree du repas (lue sur l'aura, ~20 s), puis change de couleur
-- a l'obtention du buff "Bien nourri" (un "+" avec l'icone monte alors en pulsant).
-- Animations 3D : SpellEffects.SetWellFedState("eating" | "fed" | nil), ancre AishCoreWellFedRing.

local addonName, ns = ...
local L = ns.L

local WellFedCircle = {}
ns.Modules.WellFedCircle = WellFedCircle

local bar, plus
local state = nil            -- nil | "eating" | "fed"
local eatStart = 0
local fedIcon = nil
local FormatStats          -- defini avec ParseStats plus bas
local sessionStats = nil      -- "+59 Polyvalence\n+40 Endurance" lu dans le tooltip (ou nil)
local foodIcon = nil          -- icone de la nourriture en cours
local previewMode, previewState = false, nil
local previewTicker = nil
local hiddenForGui = false
local introT = nil           -- animation d'arrivee (slide depuis le bas + fondu), secondes ecoulees
local INTRO, INTRO_RISE = 0.85, 22
local fadeT = nil            -- fondu de sortie en cours (secondes ecoulees)
local FADE = 0.35
local VERTICAL_CROP_H = 0.88
local FILL_INVERSE = { cw = "ccw", ccw = "cw", mirror_out = "mirror_in", mirror_in = "mirror_out", vertical = "vertical" }
local FED_DELAY = 10          -- valeurs par defaut : le buff arrive apres ~10 s, le repas dure ~20 s
local EAT_TOTAL = 20
-- Repas en cours : duree totale et delai du buff, lus sur l'aura et le tooltip quand c'est possible
local sessionTotal, sessionDelay = EAT_TOTAL, FED_DELAY
local pendingTotal, pendingExp = nil, nil
local sessionEatInst, sessionEatExp = nil, nil   -- repas en cours : un autre = nouveau repas (meme nourriture enchainee)
local sessionNoBuff = false     -- nourriture sans buff affichee quand meme (option) : jamais de passage au vert
local sessionKnownFed = false   -- le tooltip de l'objet annonce le buff : on peut le declarer a l'heure meme s'il est deja present
local FALLBACK_ICON = "Interface\\Icons\\INV_Misc_Food_15"

-- Detection des auras : IDs connus + noms localises derives de ces IDs (les noms ne dependent pas de la langue du client).
-- Repli : un buff apparu pendant le repas, vers la fin du delai, est pris pour "Bien nourri".
local EAT_IDS = { [433] = true, [434] = true, [435] = true, [1131] = true, [192002] = true, [396920] = true }
local FED_IDS = { [19705] = true, [19706] = true, [19708] = true, [19709] = true, [19710] = true, [19711] = true,
                  [24869] = true, [104280] = true, [462179] = true }
local eatNames, fedNames = {}, {}
local function FillNames(ids, out)
  if not (C_Spell and C_Spell.GetSpellName) then return end
  for id in pairs(ids) do
    local n = C_Spell.GetSpellName(id)
    if n then out[n] = true end
  end
end

-- /aishwf : journal de diagnostic (pourquoi et quand le cercle passe en "buff obtenu")
local wfDebug = false
local function WFDBG(fmt, ...)
  if wfDebug then print("|cff33ff99[BienNourri]|r " .. string.format(fmt, ...)) end
end
SLASH_AISHWF1 = "/aishwf"
SlashCmdList["AISHWF"] = function()
  wfDebug = not wfDebug
  print("|cff33ff99[BienNourri]|r journal " .. (wfDebug and "ACTIVE : mange quelque chose" or "coupe"))
end

local function Cfg()
  local c = ns.GetCfg("wellFedCircle")
  -- Migration : la taille de l'icone du buff etait liee a la taille du "+" ; elle devient un reglage a part, repris de l'ancienne valeur
  if c and not c.plusIconV2 then c.plusIconSize = c.plusSize or 22; c.plusIconV2 = true end
  return c
end

-- Arc radial natif (meme systeme que OutOfCombatResourceCircle.lua)
local function SetupRadialArc(sb)
  ns.SetSmoothStatusBarTexture(sb, ns.Media.circle)
  sb:SetRenderMode(Enum.StatusBarRenderMode.Radial)
  local raw = sb.SetMinMaxValues
  sb._k = 1
  sb.SetMinMaxValues = function(self, lo, hi)
    self._ulo, self._uhi = lo, hi
    raw(self, lo, hi * (self._k or 1))
  end
end

local function SetArcAngle(sb, startDeg, endDeg, reverse)
  local a0, a1 = tonumber(startDeg) or 0, tonumber(endDeg) or 359
  local span = (a1 - a0) % 360
  if span < 1 then span = 360 end
  local tex = sb:GetStatusBarTexture()
  if tex and tex.SetRadialProgressBarReverse then
    sb:SetReverseFill(false)
    tex:SetRadialProgressBarReverse(reverse and true or false)
  else
    sb:SetReverseFill(reverse and true or false)
  end
  if tex then tex:SetRotation(-math.rad(reverse and a1 or a0)) end
  local k = 360 / span
  if sb._k ~= k then
    sb._k = k
    pcall(sb.SetMinMaxValues, sb, sb._ulo or 0, sb._uhi or 100)
  end
end

local function ApplyArcAngles()
  if not bar then return end
  local cfg = Cfg()
  local mode = cfg.arcFillMode or "cw"
  local inverted = cfg.arcFillInverted == true
  if inverted then mode = FILL_INVERSE[mode] or mode end
  local mirror = (mode == "mirror_out" or mode == "mirror_in")
  bar.arc:SetShown(mode ~= "vertical")
  bar.arc2:SetShown(mirror)
  bar.arcV:SetShown(mode == "vertical")
  bar.arcV:SetReverseFill(inverted)
  if mode == "vertical" then return end
  local a0, a1 = tonumber(cfg.arcStartAngle) or 0, tonumber(cfg.arcEndAngle) or 359
  if mirror then
    local half = math.max(1, math.min(a1, 180))
    local out = (mode == "mirror_out")
    SetArcAngle(bar.arc,  a0, a0 + half, not out)
    SetArcAngle(bar.arc2, a0 - half, a0, out)
  else
    SetArcAngle(bar.arc, a0, a1, mode == "ccw")
  end
end

local function SetPct(pct, instant)
  if not bar then return end
  for _, a in ipairs({ bar.arc, bar.arc2, bar.arcV }) do
    if instant then pcall(a.SetValue, a, pct) else ns.SmoothBarValue(a, pct) end
  end
end

local function ApplyColor(c)
  c = c or { 1, 1, 1, 1 }
  for _, a in ipairs({ bar.arc, bar.arc2, bar.arcV }) do
    a:SetStatusBarColor(c[1], c[2], c[3], c[4] or 1)
  end
  if bar.bgGlow then bar.bgGlow:SetVertexColor(c[1], c[2], c[3], 1) end
end

-- ============================================================
-- "+" et icone : montee de 4 s avec leger pulse
-- ============================================================
local function EnsurePlus()
  if plus then return plus end
  local f = CreateFrame("Frame", "AishCoreWellFedPlus", UIParent)
  f:SetFrameStrata("HIGH")
  f:SetSize(10, 10)
  f.text = f:CreateFontString(nil, "OVERLAY")
  f.text:SetFont(ns.Media.font, 22, "OUTLINE")   -- police posee AVANT SetText (sinon "Font not set"), la police choisie suit dans PlayPlus
  f.text:SetPoint("RIGHT", f, "CENTER", 0, 0)
  f.textRing = ns.CreateSlugRing(f, f.text, "ARTWORK")   -- contour "Slug" (calque ARTWORK : sous le texte, qui est en OVERLAY)
  for _, r in ipairs(f.textRing) do r:SetFont(ns.Media.font, 22, ""); r:Hide() end   -- police AVANT le SetText relaye par le hook
  f.text:SetText("+")
  f.icon = f:CreateTexture(nil, "OVERLAY")
  f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  f.icon:SetPoint("LEFT", f, "CENTER", 4, 0)
  f.stats = f:CreateFontString(nil, "OVERLAY")
  f.stats:SetFont(ns.Media.font, 11, "OUTLINE")
  f.stats:SetJustifyH("LEFT")
  f.statsRing = ns.CreateSlugRing(f, f.stats, "ARTWORK")
  for _, r in ipairs(f.statsRing) do r:SetFont(ns.Media.font, 11, ""); r:Hide() end
  f:Hide()
  plus = f   -- expose seulement une fois complet : une erreur en cours de route ne laisse pas un cadre a moitie construit
  return f
end

local function StopPlus()
  if plus then plus:SetScript("OnUpdate", nil); plus:Hide() end
end

local RISE = 46
local plusPinned = false

-- ApplyFontReliable planifie des relances : on ne l'appelle que si police ou taille changent (reglages en direct)
local function OutlineFlags(style)
  if style == "THICKOUTLINE" then return "THICKOUTLINE" elseif style == "NONE" or style == "SLUG" then return "" end
  return "OUTLINE"
end

local function SetRingShown(ring, shown)
  if not ring then return end
  for _, r in ipairs(ring) do r:SetShown(shown) end
end

-- Pose directe de la police, sans passer par ApplyFontReliable (dont le repli sur un objet Font ramenait la 2002 par-dessus
-- une police pourtant valide). SetFont renvoie false quand la police est refusee : on affiche alors la 2002 le temps de
-- reessayer la vraie police a 0,3 / 1 / 3 / 8 s.
local function SetFontDirect(fs, getPath, getSize, flags, token)
  local function try()
    local ok, ret = pcall(fs.SetFont, fs, getPath(), getSize(), flags)
    return ok and ret ~= false
  end
  if try() then return end
  pcall(fs.SetFont, fs, ns.FONT_FALLBACK, getSize(), flags)
  for _, d in ipairs({ 0.3, 1, 3, 8 }) do
    C_Timer.After(d, function()
      if fs._fk ~= token or fs._fontOk == token then return end
      if try() then
        fs._fontOk = token
        local t = fs:GetText()
        if t then fs:SetText(t) end
      end
    end)
  end
end

-- ring : copies noires decalees du texte (style "Slug") ; visibles seulement avec ce style
local function ApplyFontOnce(fs, key, path, size, outline, ring)
  local flags = OutlineFlags(outline)
  local k = tostring(path) .. "|" .. tostring(size) .. "|" .. tostring(outline)
  if fs._fk == k then return end
  fs._fk = k
  local function pathFn() local c = Cfg(); return c and c[key == "WellFedPlus" and "plusFont" or "statsFont"] or ns.Media.font end
  local function sizeFn() local c = Cfg(); return c and c[key == "WellFedPlus" and "plusSize" or "statsSize"] or 12 end
  SetFontDirect(fs, pathFn, sizeFn, flags, k)
  local t = fs:GetText()
  if t then fs:SetText(t) end   -- force la mise en page avec la nouvelle police
  if ring then
    local slug = (outline == "SLUG")
    for _, r in ipairs(ring) do
      if slug then
        r._fk = k
        SetFontDirect(r, pathFn, sizeFn, "", k)
        r:SetTextColor(0, 0, 0, 1)
      end
      r:SetShown(slug)
    end
  end
end

-- pin = true : reglage dans le GUI, le "+" reste affiche a sa position finale (sans suivre le cycle du cercle)
local function PlayPlus(pin)
  local cfg = Cfg()
  if not (bar and cfg.showPlus ~= false) then return end
  local p = EnsurePlus()
  plusPinned = pin and true or false
  local size = cfg.plusIconSize or cfg.plusSize or 22   -- taille de l'icone (le "+" suit plusSize)
  ApplyFontOnce(p.text, "WellFedPlus", cfg.plusFont, cfg.plusSize, cfg.plusOutline, p.textRing)
  local fc = cfg.fedColor or { 0.1, 0.85, 0.8, 1 }
  p.text:SetTextColor(fc[1], fc[2], fc[3], 1)
  p.icon:SetTexture(fedIcon or FALLBACK_ICON)
  p:SetScale(1)
  -- Stats du buff (lues dans le tooltip), a droite de l'icone
  local statsList = sessionStats
  if not statsList and previewMode then
    statsList = { { v = "59", label = CR_VERSATILITY_DAMAGE_DONE or "Versatility", key = "SETTINGS_WF_ST_VERS" },
                  { v = "40", label = SPELL_STAT3_NAME or "Stamina", key = "SETTINGS_WF_ST_STA" } }
  end
  local statsText = FormatStats(statsList, cfg.statsShort)
  if cfg.showStats ~= false and statsText then
    ApplyFontOnce(p.stats, "WellFedStats", cfg.statsFont, cfg.statsSize, cfg.statsOutline, p.statsRing)
    local sc = cfg.statsColor or { 1, 1, 1, 1 }
    p.stats:SetTextColor(sc[1], sc[2], sc[3], sc[4] or 1)
    p.stats:ClearAllPoints()
    p.stats:SetPoint("LEFT", p, "CENTER", 4 + size + 6, 0)
    p.stats:SetText(statsText)
    p.stats:Show()
    SetRingShown(p.statsRing, cfg.statsOutline == "SLUG")
  else
    p.stats:Hide()
    SetRingShown(p.statsRing, false)
  end
  local dur = math.max(0.5, cfg.plusDuration or 4)
  local t0 = GetTime()
  p:SetAlpha(pin and 1 or 0); p:Show()
  p:SetScript("OnUpdate", function(self)
    local real = GetTime() - t0
    local t = pin and dur or real
    if t >= dur and not pin then return StopPlus() end
    local u = math.min(1, t / dur)
    -- Arrivee rapide puis gros amorti (expo-out) : l'essentiel de la montee en moins d'une seconde, fin tres lente
    local ease = (1 - 2 ^ (-8 * u)) / (1 - 2 ^ -8)
    local a = pin and 1 or math.min(1, t / 0.15) * math.min(1, (dur - t) / 0.8)
    local cx, cy = bar:GetCenter()
    if not cx then return end
    local es = UIParent:GetEffectiveScale()
    local bs = bar:GetEffectiveScale()
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT",
      (cx * bs / es) + (cfg.plusX or 0),
      (cy * bs / es) + (cfg.plusY or 0) + (cfg.size or 28) * 0.5 + 8 + RISE * ease)
    -- Seule l'icone pulse (lentement) ; le "+" reste fixe
    local s = 1 + 0.08 * math.sin(real * 2 * math.pi * 0.8)
    self.icon:ClearAllPoints()
    self.icon:SetPoint("CENTER", self, "CENTER", 4 + size / 2, 0)
    self.icon:SetSize(size * s, size * s)
    self:SetAlpha(a)
  end)
end

-- ============================================================
-- Etat
-- ============================================================
local function NotifyFX(s)
  local SE = ns.Modules and ns.Modules.SpellEffects
  if SE and SE.SetWellFedState then SE.SetWellFedState(s) end
end

-- Icone de la nourriture (option) : taille relative au cercle, visible tant que le cercle l'est
local function ApplyFoodIcon()
  if not (bar and bar.foodFrame) then return end
  local cfg = Cfg()
  if cfg.showFoodIcon and state then
    local px = (cfg.size or 28) * (cfg.foodIconScale or 0.6)
    bar.foodTex:SetSize(px, px)
    bar.foodTex:SetTexture(foodIcon or fedIcon or FALLBACK_ICON)
    bar.foodFrame:Show()
  else
    bar.foodFrame:Hide()
  end
end

local function ShowBar()
  local fresh = (not bar:IsShown()) or fadeT ~= nil
  fadeT = nil
  if fresh and bar._bx then
    introT = 0
    bar:SetAlpha(0)
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", bar._bx, bar._by - INTRO_RISE)
  elseif not introT then
    bar:SetAlpha(1)
  end
  bar:Show()
end

local function SetState(newState)
  if newState == state then return end
  local old = state
  state = newState
  if not bar then return end
  local cfg = Cfg()
  if state == "eating" then
    eatStart = (pendingExp and pendingTotal) and (pendingExp - pendingTotal) or GetTime()
    ApplyColor(cfg.eatingColor)
    SetPct(100, true)
    ShowBar()
    ApplyFoodIcon()
    NotifyFX("eating")
  elseif state == "fed" then
    ApplyColor(cfg.fedColor)
    ShowBar()
    ApplyFoodIcon()
    NotifyFX("fed")
    PlayPlus()
  else
    NotifyFX(nil)
    if old and bar:IsShown() then fadeT = 0 else bar:Hide() end
  end
end

-- Avancement du cercle pendant le repas + fondu de sortie (OnUpdate leger, uniquement tant que le cercle est affiche)
local function OnBarUpdate(self, dt)
  if introT then
    introT = introT + dt
    local u = math.min(1, introT / INTRO)
    local e = 1 - (1 - u) ^ 4   -- ease-out quartique : depart vif, arrivee tres douce
    self:SetAlpha(e)
    self:ClearAllPoints()
    self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", self._bx, self._by - INTRO_RISE * (1 - e))
    if u >= 1 then introT = nil end
    return
  end
  if fadeT then
    fadeT = fadeT + dt
    if fadeT >= FADE then fadeT = nil; self:Hide(); return end
    self:SetAlpha(1 - fadeT / FADE)
    return
  end
  -- Buff garanti par le tooltip : declare a l'heure, quel que soit l'etat de l'aura (deja presente, refresh...)
  if state == "eating" and sessionKnownFed and not previewMode and GetTime() - eatStart >= sessionDelay + 0.3 then
    fedIcon = fedIcon or foodIcon
    WFDBG("BUFF via [1] heure du tooltip : %.1f s ecoulees (delai lu %s s)", GetTime() - eatStart, tostring(sessionDelay))
    SetState("fed")
  end
  if state and not (previewMode and previewState) then
    local cfg = Cfg()
    local p = math.min(1, (GetTime() - eatStart) / math.max(1, sessionTotal))
    if previewMode then p = p * 0.5 end   -- apercu : jamais en dessous de 50 %, le cercle reste visible et reglable
    SetPct((1 - p) * 100, true)
  end
end

-- ============================================================
-- Detection reelle
-- ============================================================
-- Nourriture qui ne donnera pas le buff : on retient le dernier objet utilise (hooks passifs sur les fonctions d'usage)
-- et on cherche "Bien nourri" dans son tooltip. Objet inconnu / tooltip illisible : on affiche le cercle par prudence.
local FED_WORDS = { "well fed", "bien nourri", "bien alimentado", "bem alimentado", "ben nutrito" }

-- Le nom du buff varie ("Bien nourri", "Personnage bien nourri"...) : nom exact connu OU contenant l'expression
local function IsFedName(name)
  if type(name) ~= "string" then return false end
  if fedNames[name] then return true end
  local l = name:lower()
  for _, w in ipairs(FED_WORDS) do
    if l:find(w, 1, true) then return true end
  end
  return false
end
local lastItemID, lastItemAt = nil, 0
local eligibleCache = {}
local skipEat = false

local lateItem   -- defini plus bas : traite un objet repere APRES le debut du repas

local function NoteItem(id)
  id = tonumber(id)
  if id then
    lastItemID, lastItemAt = id, GetTime()
    if lateItem then lateItem(id) end
  end
end

do
  if C_Container and C_Container.UseContainerItem and C_Container.GetContainerItemID then
    hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
      NoteItem(C_Container.GetContainerItemID(bag, slot))
    end)
  end
  if UseAction and GetActionInfo then
    hooksecurefunc("UseAction", function(slot)
      local t, id = GetActionInfo(slot)
      if t == "item" then
        NoteItem(id)
      elseif t == "macro" and GetMacroItem then
        local _, link = GetMacroItem(id)
        NoteItem(link and tonumber(link:match("item:(%d+)")))
      end
    end)
  end
  if UseItemByName then
    hooksecurefunc("UseItemByName", function(name)
      local info = C_Item and C_Item.GetItemInfoInstant and C_Item.GetItemInfoInstant(name)
      NoteItem(info)
    end)
  end
end

-- Les clics dans les sacs passent par des boutons securises (aucune fonction a hooker) : on repere donc la nourriture
-- consommee par la baisse de son stock dans les sacs (Consommable > Nourriture & boissons).
do
  local isFood = {}
  local snap = {}
  local function Snapshot()
    local out = {}
    local last = NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4
    for bag = 0, last do
      for slot = 1, C_Container.GetContainerNumSlots(bag) do
        local info = C_Container.GetContainerItemInfo(bag, slot)
        local id = info and info.itemID
        if id then
          local f = isFood[id]
          if f == nil then
            local _, _, _, _, _, classID, subID = C_Item.GetItemInfoInstant(id)
            f = (classID == 0 and subID == 5)
            isFood[id] = f
          end
          if f then out[id] = (out[id] or 0) + (info.stackCount or 1) end
        end
      end
    end
    return out
  end
  if C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerItemInfo
     and C_Item and C_Item.GetItemInfoInstant then
    local f = CreateFrame("Frame")
    f:RegisterEvent("BAG_UPDATE_DELAYED")
    f:RegisterEvent("PLAYER_ENTERING_WORLD")
    f:SetScript("OnEvent", function(_, event)
      if UnitAffectingCombat("player") then return end
      local ok, now = pcall(Snapshot)
      if not ok then return end
      if event ~= "PLAYER_ENTERING_WORLD" then
        for id, n in pairs(snap) do
          if (now[id] or 0) < n then NoteItem(id); break end
        end
      end
      snap = now
    end)
  end
end

-- Secondes citees dans un texte ("20 s", "10 sec", "10 seconds"), dans l'ordre
-- Espaces insecables (francais : "10 s") ramenes a des espaces, sinon %s ne les reconnait pas
local function NormSpaces(text)
  return (text:gsub("\194\160", " "):gsub("\226\128\175", " "))
end

-- Secondes citees dans un texte ("20 s", "10 sec", "10 seconds"), dans l'ordre d'apparition.
-- Renvoie aussi la position de chacune (pour retrouver celle qui precede "bien nourri").
local function Seconds(text)
  text = NormSpaces(text)
  local found = {}
  for pos, n in text:gmatch("()(%d+)%s*s%f[%A]") do found[#found + 1] = { pos = pos, v = tonumber(n) } end
  for pos, n in text:gmatch("()(%d+)%s*sec") do found[#found + 1] = { pos = pos, v = tonumber(n) } end
  table.sort(found, function(a, b) return a.pos < b.pos end)
  local out, at = {}, {}
  for i, f in ipairs(found) do out[i], at[i] = f.v, f.pos end
  return out, at
end

-- Stats du buff : noms de stats localises du client (globales Blizzard), nombre le plus proche de chacun.
-- "bonus de 59 a la Polyvalence" (nombre avant) comme "Haste by 59" (nombre apres). Durees et pourcentages ecartes.
local STAT_GLOBALS = {
  { "SPELL_STAT1_NAME", "SETTINGS_WF_ST_STR" }, { "SPELL_STAT2_NAME", "SETTINGS_WF_ST_AGI" },
  { "SPELL_STAT3_NAME", "SETTINGS_WF_ST_STA" }, { "SPELL_STAT4_NAME", "SETTINGS_WF_ST_INT" },
  { "SPELL_STAT5_NAME", "SETTINGS_WF_ST_SPI" }, { "CR_CRIT_MELEE", "SETTINGS_WF_ST_CRIT" },
  { "CR_HASTE_MELEE", "SETTINGS_WF_ST_HASTE" }, { "CR_MASTERY", "SETTINGS_WF_ST_MAST" },
  { "CR_VERSATILITY_DAMAGE_DONE", "SETTINGS_WF_ST_VERS" }, { "ITEM_MOD_VERSATILITY", "SETTINGS_WF_ST_VERS" },
  { "ITEM_MOD_ATTACK_POWER_SHORT", "SETTINGS_WF_ST_AP" }, { "STAT_ATTACK_POWER", "SETTINGS_WF_ST_AP" },
  { "ITEM_MOD_SPELL_POWER_SHORT", "SETTINGS_WF_ST_SP" }, { "STAT_SPELLPOWER", "SETTINGS_WF_ST_SP" },
}

-- Renvoie une liste { v = "59", label = "Polyvalence", key = cle de locale du nom court } ou nil
local function ParseStats(text)
  if type(text) ~= "string" or text == "" then return nil end
  text = text:lower()
  text = text:gsub("%d+%s*s%f[%A]", ""):gsub("%d+%s*sec%a*", ""):gsub("%d+%s*heures?", ""):gsub("%d+%s*hours?", "")
             :gsub("%d+%s*min%a*", ""):gsub("%d+%s*h%f[%A]", ""):gsub("%d+%s*%%", "")
  local nums = {}
  for pos, n in text:gmatch("()(%d+)") do nums[#nums + 1] = { pos = pos, v = n } end
  local stats, seen = {}, {}
  for _, def in ipairs(STAT_GLOBALS) do
    local label = _G[def[1]]
    if type(label) == "string" and label ~= "" and not seen[label] then
      seen[label] = true
      local pos = text:find(label:lower(), 1, true)
      if pos then stats[#stats + 1] = { pos = pos, label = label, key = def[2] } end
    end
  end
  table.sort(stats, function(a, b) return a.pos < b.pos end)
  local out = {}
  for _, st in ipairs(stats) do
    local best, bd
    for _, n in ipairs(nums) do
      if not n.used then
        local d = math.abs(n.pos - st.pos)
        if not bd or d < bd then best, bd = n, d end
      end
    end
    if best then best.used = true; out[#out + 1] = { v = best.v, label = st.label, key = st.key } end
  end
  return #out > 0 and out or nil
end

-- "+59 Polyvalence" par ligne ; option "tronquer" : nom court ("Poly")
FormatStats = function(list, short)
  if not list then return nil end
  local lines = {}
  for _, st in ipairs(list) do
    lines[#lines + 1] = "+" .. st.v .. " " .. ((short and L[st.key]) or st.label)
  end
  return table.concat(lines, "\n")
end

local function AuraStats(inst)
  if not (inst and C_TooltipInfo and C_TooltipInfo.GetUnitBuffByAuraInstanceID) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetUnitBuffByAuraInstanceID, "player", inst)
  if not ok or not data or not data.lines then return nil end
  local parts = {}
  for _, line in ipairs(data.lines) do
    local t = line.leftText
    if type(t) == "string" and not (issecretvalue and issecretvalue(t)) then parts[#parts + 1] = t end
  end
  return ParseStats(table.concat(parts, " "))
end

-- { fed = bool, total = secondes|nil, delay = secondes|nil, stats = texte|nil } ou nil (inconnu)
local function ItemFoodInfo(itemID)
  local cached = eligibleCache[itemID]
  if cached ~= nil then return cached end
  if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then return nil end
  local ok, data = pcall(C_TooltipInfo.GetItemByID, itemID)
  if not ok or not data or not data.lines then return nil end
  if not next(fedNames) then FillNames(FED_IDS, fedNames) end
  local found, total, delay, fedText, fedLine = false, nil, nil, "", nil
  for _, line in ipairs(data.lines) do
    local text = line.leftText
    if type(text) == "string" and not (issecretvalue and issecretvalue(text)) then
      text = NormSpaces(text:lower())
      local isFedLine, fedPos = false, nil
      for _, w in ipairs(FED_WORDS) do
        local fp = text:find(w, 1, true)
        if fp then isFedLine, fedPos = true, fp; break end
      end
      if not isFedLine then
        for n in pairs(fedNames) do
          local fp = text:find(n:lower(), 1, true)
          if fp then isFedLine, fedPos = true, fp; break end
        end
      end
      if isFedLine then
        found = true
        -- Delai = duree plausible (5-60 s) la plus proche AVANT "bien nourri" ("au moins 10 s a manger, ... bien
        -- nourri"). Sur Forever tout le texte d'utilisation tient sur une ligne, qui cite aussi la duree du repas
        -- ("en 18 sec") : la premiere duree trouvee n'est donc pas forcement la bonne. Repli : premiere plausible.
        if not delay then
            local vals, poss = Seconds(text)
            for i = #vals, 1, -1 do
                if poss[i] < fedPos and vals[i] >= 5 and vals[i] <= 60 then delay = vals[i]; break end
            end
            if not delay then
                for _, v in ipairs(vals) do
                    if v >= 5 and v <= 60 then delay = v; break end
                end
            end
        end
        if text:find("%d") then fedLine = fedLine or text end   -- diagnostic /aishwf
        if text:find("%d") then fedText = fedText .. " " .. text end
      elseif not total then
        local secs = Seconds(text)
        total = secs[#secs]
      end
    end
  end
  local info = { fed = found, total = total, delay = delay, stats = found and ParseStats(fedText) or nil, line = fedLine }
  eligibleCache[itemID] = info
  return info
end

-- Objet repere apres le debut du repas (baisse du stock en sac, plus lente que l'aura) : icone, et nourriture sans buff
lateItem = function(id)
  if state ~= "eating" or GetTime() - eatStart > 4 then return end
  local info = ItemFoodInfo(id)
  if info and info.fed == false then
    if Cfg().showWithoutBuff then
      sessionNoBuff = true
    else
      skipEat = true
      SetState(nil)
      return
    end
  end
  sessionKnownFed = info ~= nil and info.fed == true
  sessionStats = info and info.stats or sessionStats
  if info then
    sessionDelay = info.delay or sessionDelay
  end
  WFDBG("OBJET repere en cours de repas : %s  tooltip buff=%s delai=%s  ligne=%s", tostring(id),
    tostring(info and info.fed), tostring(info and info.delay), tostring(info and info.line))
  local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
  if icon then foodIcon = icon; ApplyFoodIcon() end
end

local knownAuras = {}
local fedNameSeen, eatNameSeen   -- diagnostic /aishwf
local fedExpAtStart = 0
local function Scan()
  if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return false, false, nil, nil, 0, nil, nil end
  if not next(eatNames) then FillNames(EAT_IDS, eatNames) end
  if not next(fedNames) then FillNames(FED_IDS, fedNames) end
  local eating, fed, icon, newBuffIcon, fedExp = false, false, nil, nil, 0
  local eatDur, eatExp, eatIcon, fedInst, eatInst
  local issecret = issecretvalue
  local fresh = {}
  for i = 1, 40 do
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
    if not ok or not a then break end
    local sid, name, inst = a.spellId, a.name, a.auraInstanceID
    if not (issecret and (issecret(sid) or issecret(name) or issecret(inst))) then
      if EAT_IDS[sid] or (name and eatNames[name]) then
        eating = true
        eatNameSeen = tostring(name) .. " #" .. tostring(sid)
        eatIcon = a.icon
        eatInst = inst
        local d, e = a.duration, a.expirationTime
        if type(d) == "number" and type(e) == "number" and not (issecret and (issecret(d) or issecret(e))) and d > 0 then
          eatDur, eatExp = d, e
        end
      elseif FED_IDS[sid] or IsFedName(name) then
        fed, icon = true, a.icon
        fedExp = tonumber(a.expirationTime) or 0
        fedInst = inst
        fedNameSeen = tostring(name) .. " #" .. tostring(sid)
      elseif inst then
        fresh[inst] = true
        if state == "eating" and not knownAuras[inst] then newBuffIcon = a.icon end
      end
    end
  end
  knownAuras = fresh
  return eating, fed, icon, newBuffIcon, fedExp, eatDur, eatExp, eatIcon, fedInst, eatInst
end

function WellFedCircle.Refresh(updateInfo)
  if previewMode then return end
  local cfg = Cfg()
  if not bar or not cfg or cfg.enabled == false or hiddenForGui
     or UnitAffectingCombat("player") or ns.IsInBlockedState() then
    if state then SetState(nil) end
    return
  end
  local eating, fed, icon, newBuffIcon, fedExp, eatDur, eatExp, eatIcon, fedInst, eatInst = Scan()
  if not eating then
    skipEat, sessionNoBuff = false, false
    sessionEatInst, sessionEatExp = nil, nil
    if state then SetState(nil) end
    return
  end
  -- Nouveau repas enchaine (autre instance d'aura ou echeance differente) : on repart de zero
  if (sessionEatInst and eatInst and eatInst ~= sessionEatInst)
     or (sessionEatExp and eatExp and math.abs(eatExp - sessionEatExp) > 1.5) then
    skipEat, sessionNoBuff = false, false
    if state then SetState(nil) end
  end
  sessionEatInst, sessionEatExp = eatInst, eatExp
  if skipEat then return end
  if state == nil then
    -- Nourriture sans buff (tooltip sans "Bien nourri") : pas de cercle pour ce repas
    local info = lastItemID and GetTime() - lastItemAt < 4 and ItemFoodInfo(lastItemID) or nil
    sessionNoBuff = false
    if info and info.fed == false then
      if cfg.showWithoutBuff then sessionNoBuff = true else skipEat = true; return end
    end
    sessionKnownFed = info ~= nil and info.fed == true
    sessionStats = info and info.stats or nil
    sessionDelay = (info and info.delay) or FED_DELAY
    sessionTotal = eatDur or (info and info.total) or EAT_TOTAL
    pendingTotal, pendingExp = eatDur, eatExp
    -- Icone de l'objet mange si on l'a reperé, sinon celle de l'aura de repas
    foodIcon = (lastItemID and GetTime() - lastItemAt < 4 and C_Item and C_Item.GetItemIconByID
      and C_Item.GetItemIconByID(lastItemID)) or eatIcon
    SetState("eating")
    fedExpAtStart = fed and fedExp or 0   -- deja bien nourri : seule une relance du buff compte
    WFDBG("REPAS : objet=%s  tooltip buff=%s delai=%s total=%s  aura repas duree=%s fin dans=%s  debut repas=-%.1f s  bien nourri deja=%s",
      tostring(lastItemID), tostring(info and info.fed), tostring(info and info.delay), tostring(info and info.total),
      tostring(eatDur), eatExp and string.format("%.1f", eatExp - GetTime()) or "nil", GetTime() - eatStart,
      fed and tostring(fedNameSeen) or "non")
    WFDBG("  aura de repas : %s  |  ligne tooltip : %s", tostring(eatNameSeen), tostring(info and info.line))
  end
  if state == "eating" and not sessionNoBuff then
    local elapsed = GetTime() - eatStart
    local dur = sessionDelay
    -- Le buff vient d'etre (re)pose, meme s'il etait deja present. Jamais avant l'heure du buff (~10 s) : sur Forever
    -- le jeu signale des "mises a jour" d'un Bien nourri deja present sans qu'il change, ce qui le faisait passer au
    -- vert des 2-3 s. Une mise a jour ne compte que si l'echeance du buff a reellement avance (vrai refresh).
    local fedEvent = false
    if updateInfo and elapsed >= dur - 1.5 then
      pcall(function()
        for _, a in ipairs(updateInfo.addedAuras or {}) do
          if FED_IDS[a.spellId] or IsFedName(a.name) then fedEvent = true end
        end
        for _, id in ipairs(updateInfo.updatedAuraInstanceIDs or {}) do
          if fedInst and id == fedInst and fedExp > fedExpAtStart + 1 then fedEvent = true end
        end
      end)
    end
    -- Repli sans reconnaitre l'aura : un buff ajoute / mis a jour vers l'heure du buff
    if not fedEvent and updateInfo and elapsed >= dur - 1.5 and elapsed <= dur + 4 then
      pcall(function()
        for _, a in ipairs(updateInfo.addedAuras or {}) do
          if not (EAT_IDS[a.spellId] or (a.name and eatNames[a.name])) then fedEvent = true; fedIcon = a.icon end
        end
        for _, id in ipairs(updateInfo.updatedAuraInstanceIDs or {}) do
          if knownAuras[id] then fedEvent = true end
        end
      end)
      if fedEvent and not fed then
        WFDBG("BUFF via [3] aura ajoutee/mise a jour vers l'heure prevue : %.1f s", elapsed)
        SetState("fed"); return
      end
    end
    -- Garde de temps aussi ici : une echeance qui "bouge" avant l'heure du buff n'est pas un vrai refresh
    if fed and elapsed >= dur - 1.5 and (fedEvent or fedExp > fedExpAtStart + 1) then
      WFDBG("BUFF via [2] aura Bien nourri (nom=%s) : %.1f s  evenement=%s expiration=%.1f (debut %.1f)",
        tostring(fedNameSeen), elapsed, tostring(fedEvent), fedExp, fedExpAtStart)
      fedIcon = icon
      sessionStats = sessionStats or AuraStats(fedInst)
      SetState("fed")
    elseif newBuffIcon and elapsed >= dur - 1.5 and elapsed <= dur + 4 then
      WFDBG("BUFF via [4] nouveau buff vers l'heure prevue : %.1f s", elapsed)
      fedIcon = newBuffIcon
      SetState("fed")
    end
  end
end

-- ============================================================
-- Creation / reglages
-- ============================================================
function WellFedCircle.ApplySettings()
  if not bar then return end
  local cfg = Cfg()
  local size = cfg.size or 28
  bar:SetSize(size, size)
  bar.bgLarge:SetSize(size * 1.1, size * 1.1)
  local arcPx = size * (cfg.arcSizeRatio or 1)
  for _, a in ipairs({ bar.arc, bar.arc2 }) do
    a:SetSize(arcPx, arcPx); a:ClearAllPoints(); a:SetPoint("CENTER", bar, "CENTER")
  end
  bar.arcV:SetSize(arcPx, arcPx * VERTICAL_CROP_H)
  bar.arcV:ClearAllPoints()
  bar.arcV:SetPoint("TOP", bar, "CENTER", 0, arcPx / 2)
  local overlayPx = arcPx * math.max(0, math.min(1 - (cfg.arcThickness or 1), 0.995))
  if overlayPx >= 2 then bar.overlay:SetSize(overlayPx, overlayPx); bar.overlay:Show() else bar.overlay:Hide() end
  bar.bgGlow:SetSize(size * 1.1 * 0.9, size * 1.1 * 0.9)
  ApplyArcAngles()
  ApplyFoodIcon()
  if bar._lastSize ~= size then
    bar._lastSize = size
    local SE = ns.Modules and ns.Modules.SpellEffects
    if SE and SE.RefreshWellFedDeco then SE.RefreshWellFedDeco() end   -- les animations suivent la taille
  end
  local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
  bar._bx, bar._by = sw * cfg.anchorPctX + cfg.x, sh * cfg.anchorPctY + cfg.y
  if not introT then
    bar:ClearAllPoints()
    bar:SetPoint("CENTER", UIParent, "BOTTOMLEFT", bar._bx, bar._by)
  end
  if state == "eating" then ApplyColor(cfg.eatingColor) elseif state == "fed" or previewState == "fed" then ApplyColor(cfg.fedColor) end
  if cfg.enabled == false then
    if state then SetState(nil) end
    bar:Hide()
    return
  end
  if previewMode then
    -- Reglage en direct : on ne relance pas le cycle (il repartirait du repas), on rejoue juste le "+" s'il est a l'ecran
    if not bar:IsShown() then WellFedCircle.SetPreview(true, previewState) end
  else
    WellFedCircle.Refresh()
  end
end

function WellFedCircle.Create(parent)
  if bar then return bar end
  local cfg = Cfg()
  bar = CreateFrame("Frame", "AishCoreWellFedRing", parent or UIParent)
  bar:SetFrameStrata("MEDIUM")
  bar:SetSize(cfg.size, cfg.size)

  local glow = bar:CreateTexture(nil, "BACKGROUND", nil, -1)
  ns.SetSmoothTexture(glow, "Interface\\AddOns\\AishCore\\Media\\Wheel\\Circle_Smooth2.tga")
  glow:SetBlendMode("ADD"); glow:SetDesaturated(true); glow:SetAlpha(0.6)
  glow:SetPoint("CENTER")
  bar.bgGlow = glow

  local bg = bar:CreateTexture(nil, "BACKGROUND")
  ns.SetSmoothTexture(bg, ns.Media.circle)
  bg:SetPoint("CENTER"); bg:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.bgLarge = bg

  local group = CreateFrame("Frame", nil, bar)
  group:SetFrameLevel(bar:GetFrameLevel() + 1)
  group:SetAllPoints(bar)
  local function NewRadial()
    local a = CreateFrame("StatusBar", nil, group)
    a:SetFrameLevel(group:GetFrameLevel())
    a:SetPoint("CENTER", bar, "CENTER")
    SetupRadialArc(a)
    a:SetMinMaxValues(0, 100); a:SetValue(0)
    return a
  end
  bar.arc, bar.arc2 = NewRadial(), NewRadial()
  local arcV = CreateFrame("StatusBar", nil, group)
  arcV:SetFrameLevel(group:GetFrameLevel())
  ns.SetSmoothStatusBarTexture(arcV, "Interface\\AddOns\\AishCore\\Media\\circle_piecrop.tga")
  arcV:SetOrientation("VERTICAL"); arcV:SetMinMaxValues(0, 100); arcV:SetValue(0)
  bar.arcV = arcV

  local ovf = CreateFrame("Frame", nil, bar)
  ovf:SetFrameLevel(group:GetFrameLevel() + 1)
  ovf:SetAllPoints(bar)
  local ov = ovf:CreateTexture(nil, "ARTWORK")
  ns.SetSmoothTexture(ov, ns.Media.circle)
  ov:SetPoint("CENTER"); ov:SetVertexColor(0x0e/255, 0x0e/255, 0x0e/255, 1)
  bar.overlay = ov

  -- Icone de la nourriture au centre, en cercle (masque), au-dessus du remplissage
  local ff = CreateFrame("Frame", nil, bar)
  ff:SetFrameLevel(ovf:GetFrameLevel() + 1)
  ff:SetAllPoints(bar)
  local ft = ff:CreateTexture(nil, "ARTWORK")
  ft:SetPoint("CENTER")
  ft:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local fm = ff:CreateMaskTexture()
  fm:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  fm:SetAllPoints(ft)
  ft:AddMaskTexture(fm)
  ff:Hide()
  bar.foodFrame, bar.foodTex = ff, ft

  bar:SetScript("OnUpdate", OnBarUpdate)
  bar:Hide()

  bar:SetScript("OnHide", function() StopPlus(); ff:Hide() end)

  local ev = CreateFrame("Frame")
  ev:RegisterUnitEvent("UNIT_AURA", "player")
  ev:RegisterEvent("PLAYER_REGEN_DISABLED")
  ev:RegisterEvent("PLAYER_REGEN_ENABLED")
  ev:RegisterEvent("PLAYER_ENTERING_WORLD")
  ev:SetScript("OnEvent", function(_, event, _, updateInfo)
    WellFedCircle.Refresh(event == "UNIT_AURA" and updateInfo or nil)
  end)

  WellFedCircle.ApplySettings()
  return bar
end

-- ============================================================
-- Apercu (panneau de reglages) : cycle repas -> bien nourri. forced = "eating" | "fed" fige l'etat
-- (utilise par la section Animations 3D pour regler chaque combo).
-- ============================================================
local function StopPreviewTicker()
  if previewTicker then previewTicker:Cancel(); previewTicker = nil end
end

function WellFedCircle.SetPreview(on, forced)
  previewMode, previewState = on and true or false, on and forced or nil
  StopPreviewTicker()
  if not bar then return end
  if not on then
    StopPlus()
    state = nil
    NotifyFX(nil)
    bar:Hide()
    WellFedCircle.Refresh()
    return
  end
  local cfg = Cfg()
  if cfg.enabled == false then bar:Hide(); return end
  if forced then
    state = nil
    SetState(forced)
    SetPct(forced == "fed" and 40 or 60, true)
    return
  end
  state = nil
  sessionTotal, sessionDelay, pendingTotal, pendingExp = EAT_TOTAL, FED_DELAY, nil, nil
  SetState("eating")
  local total = EAT_TOTAL
  local t0 = GetTime()
  previewTicker = C_Timer.NewTicker(0.1, function()
    local t = (GetTime() - t0) % total   -- cycle continu : le cercle ne disparait jamais
    if t < FED_DELAY then
      if state ~= "eating" then SetState(nil); SetState("eating") end
    elseif state ~= "fed" then
      SetState("fed")
    end
  end)
end

function WellFedCircle.SetGuiHidden(on)
  hiddenForGui = on and true or false
  WellFedCircle.Refresh()
end

function WellFedCircle.SetDraggable(on)
  if not bar then return end
  if on then
    bar:SetMovable(true); bar:EnableMouse(true); bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function(self)
      local c = Cfg()
      if c and c.locked then return end
      self:StartMoving()
    end)
    bar:SetScript("OnDragStop", function(self)
      self:StopMovingOrSizing()
      local cx, cy = self:GetCenter()
      local sw, sh = UIParent:GetWidth(), UIParent:GetHeight()
      local db = ns.DB.wellFedCircle
      db.anchorPctX, db.anchorPctY, db.x, db.y = cx / sw, cy / sh, 0, 0
      self:ClearAllPoints()
      self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", cx, cy)
      self._bx, self._by = cx, cy
    end)
    if not bar._dragBorder then
      local b = bar:CreateTexture(nil, "OVERLAY", nil, 7)
      b:SetAllPoints(bar); b:SetColorTexture(1, 1, 1, 0.15)
      bar._dragBorder = b
    end
    bar._dragBorder:Hide()
    bar:SetScript("OnEnter", function(self)
      local c = Cfg()
      if not (c and c.locked) then self._dragBorder:Show() end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText(L["RESOURCE_DRAG_TOOLTIP"])
      GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", function(self) self._dragBorder:Hide(); GameTooltip:Hide() end)
  else
    bar:SetMovable(false); bar:EnableMouse(false); bar:RegisterForDrag()
    bar:SetScript("OnDragStart", nil); bar:SetScript("OnDragStop", nil)
    bar:SetScript("OnEnter", nil); bar:SetScript("OnLeave", nil)
    if bar._dragBorder then bar._dragBorder:Hide() end
  end
end

function WellFedCircle.ResetPosition()
  local db, def = ns.DB.wellFedCircle, ns.Defaults.wellFedCircle
  db.anchorPctX, db.anchorPctY, db.x, db.y = def.anchorPctX, def.anchorPctY, def.x, def.y
  WellFedCircle.ApplySettings()
end

-- Reglage du "+", de l'icone ou des stats dans le GUI : on les affiche a leur position finale, independamment du cycle,
-- tant que les reglages bougent (disparaissent 5 s apres le dernier changement)
local pinToken = 0
function WellFedCircle.PinPlus()
  if not (bar and previewMode) or not bar:IsShown() then return end
  pinToken = pinToken + 1
  local token = pinToken
  PlayPlus(true)
  C_Timer.After(5, function()
    if token == pinToken and plusPinned then StopPlus(); plusPinned = false end
  end)
end

-- Bouton "Apercu du buff" : passe le cercle en etat "buff obtenu" (couleur, animations 3D, "+" et icone), puis relance le cycle
local previewToken = 0
function WellFedCircle.PreviewBuff()
  if not (bar and previewMode) or Cfg().enabled == false then return end
  StopPreviewTicker()
  previewToken = previewToken + 1
  local token = previewToken
  state = nil
  fedIcon = nil
  SetState("fed")
  SetPct(60, true)
  C_Timer.After(math.max(1, Cfg().plusDuration or 4) + 2, function()
    if token == previewToken and previewMode and not previewState then WellFedCircle.SetPreview(true) end
  end)
end

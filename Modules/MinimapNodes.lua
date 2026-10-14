-- Modules/MinimapNodes.lua : "Herbes et minerais sur la minimap" -- remplace les points du pistage (Dénicher les herbes /
-- les minerais) par l'icone de chaque plante ou filon.
-- Le jeu ne dit pas ou sont les points : on les trouve en passant la souris "virtuelle" sur une grille de points de la
-- minimap (Minimap:UpdateMouseoverAtPoint, utilisable avec le curseur souple de la minimap), l'infobulle de la minimap
-- (C_TooltipInfo.GetMinimapMouseover) donnant le nom des points qui s'y trouvent. Les points voisins portant le meme nom
-- sont regroupes en un seul endroit, qu'on suit ensuite en coordonnees du monde pour que l'icone bouge avec nous.
-- Les noms sont reconnus a partir des noms d'objets du client (donc dans sa langue) : une plante porte le nom de son objet,
-- un filon celui de son minerai ("Filon de cuivre" / "Minerai de cuivre"). Sinon : icone generique du pistage actif.
local addonName, ns = ...

ns.Modules = ns.Modules or {}
local MN = {}
ns.Modules.MinimapNodes = MN

local STEP       = 10    -- ecart entre deux points essayes (unites de minimap)
local PER_FRAME  = 20    -- points essayes par image
local SCAN_WAIT  = 2.0   -- secondes entre deux balayages
local IDLE_WAIT  = 4.0   -- idem quand rien n'est a chercher (pas de pistage, combat...)
local MERGE      = 15    -- verges : un endroit revu a moins que ca garde sa place (moyennee)
local SINGLE_MAX = 9     -- au plus de points qu'un seul point de minimap donne (au dela : plusieurs)

-- Pistages qui montrent des herbes / minerais (sorts "Denicher les herbes" / "Denicher les mineraux")
local FINDERS = { [2383] = "herbs", [2580] = "ore" }

-- Objets (identifiants, donc independants de la langue) dont on tire le nom localise et l'icone. Plante : son nom
-- d'objet est celui de la plante. Filon : le nom du minerai sans son "Minerai de".
local HERB_ITEMS = {
  2447, 765, 2449, 785, 2450, 3820, 2453, 3355, 3369, 3356, 3357, 3818, 3821, 3358, 3819, 4625, 8831, 8836, 8838, 8839,
  8845, 8846, 13464, 13463, 13465, 13466, 13467, 13468,                       -- classique
  22785, 22786, 22787, 22788, 22789, 22790, 22791, 22792, 22793,              -- Outreterre
  36901, 36903, 36904, 36905, 36906, 36907, 36908, 37921, 39970,              -- Norfendre
}
local ORE_ITEMS = {
  2770, 2771, 2775, 2772, 2776, 3858, 7911, 10620, 11370,                     -- classique
  23424, 23425, 23426, 23427,                                                 -- Outreterre
  36909, 36910, 36912,                                                        -- Norfendre
}
local GENERIC_ITEM = { herbs = 2447, ore = 2770 }   -- icone quand le nom n'est pas reconnu

local function Cfg()
  return ns.GetCfg("minimapNodes") or {}
end

-- Nom / icone d'un objet, quelle que soit l'API presente sur ce client
local function ItemName(id)
  if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
  return (GetItemInfo and GetItemInfo(id)) or nil
end
local function ItemIcon(id)
  if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
  if GetItemIcon then return GetItemIcon(id) end
  return nil
end

MN._dbg = { probes = 0, withData = 0, names = {}, found = 0, scans = 0, sample = {} }

local function IsSecret(v)
  return issecretvalue and issecretvalue(v)
end

-- Appels de minimap dont le balayage a besoin, et ceux qui manquent sur ce client
function MN.Missing()
  local missing = {}
  if Minimap == nil then return { "Minimap" } end
  if Minimap.UpdateMouseoverAtPoint == nil then missing[#missing + 1] = "Minimap:UpdateMouseoverAtPoint" end
  if Minimap.SetUsingSoftCursor == nil then missing[#missing + 1] = "Minimap:SetUsingSoftCursor" end
  if C_TooltipInfo == nil or C_TooltipInfo.GetMinimapMouseover == nil then missing[#missing + 1] = "C_TooltipInfo.GetMinimapMouseover" end
  return missing
end

function MN.Available()
  return #MN.Missing() == 0
end

-- Reconnaissance des noms ---------------------------------------------------------------------------
local function Plain(s)
  s = tostring(s)
  -- Codes d'affichage : |cAARRGGBB, |r, |Ttexture|t, |Hlien|h...|h
  s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|H.-|h", ""):gsub("|h", "")
  return (s:lower():gsub("\226\128\152", "'"):gsub("\226\128\153", "'"))
end

-- Nom d'une ligne d'infobulle sans ses codes d'affichage ni espaces autour. Le jeu fait preceder le nom d'une fleche
-- (|T...|t) quand la plante est plus haut ou plus bas que toi : sans ce nettoyage, la meme plante change de nom
-- selon ton altitude et n'est plus reconnue.
local function Clean(text)
  return (Plain(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "copper ore" -> "copper", "minerai de cuivre" -> "cuivre"
local function OreKey(key)
  key = key:gsub("%s+ore$", ""):gsub("^minerai d[e']%s*", ""):gsub("^mineral de%s+", ""):gsub("erz$", "")
  return key
end

local index, indexMissing = {}, true
local function BuildIndex()
  local list, missing = {}, false
  local function Add(ids, kind)
    for _, id in ipairs(ids) do
      local name = ItemName(id)
      if not name then
        missing = true
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
      else
        local key = Plain(name)
        if kind == "ore" then key = OreKey(key) end
        if #key >= 3 then list[#list + 1] = { key = key, kind = kind, id = id } end
      end
    end
  end
  Add(HERB_ITEMS, "herbs")
  Add(ORE_ITEMS, "ore")
  -- Cle la plus longue d'abord : "dark iron" avant "iron", "silverleaf" avant "silver"
  table.sort(list, function(a, b) return #a.key > #b.key end)
  index, indexMissing = list, missing
end

-- kind, icone d'un nom de point ; `only` = le seul pistage actif (repli pour un nom inconnu), nil sinon
-- `finderKind` : genre du seul pistage "Denicher" actif ; un nom marque "???" (point non identifie) en prend l'icone generique
local function Resolve(name, only, finderKind)
  local l = Plain(name):gsub("^[^%a\128-\255]+", "")
  if l:find("[%d:]") then return nil end            -- "Fleur de paix 3/8" : une quete, pas une plante
  for _, e in ipairs(index) do
    local hit
    if e.kind == "ore" then hit = l:find("%f[%a]" .. e.key:gsub("%p", "%%%0") .. "%f[%A]") else hit = l:find(e.key, 1, true) end
    if hit then return e.kind, ItemIcon(e.id), e.id end
  end
  if only then return only, ItemIcon(GENERIC_ITEM[only]) end
  if finderKind and tostring(name):find("^%?%?%?") then return finderKind, ItemIcon(GENERIC_ITEM[finderKind]) end
  return nil
end

-- Pistages actifs : nombre total, et genre du seul pistage actif s'il s'agit d'un Denicher
-- Renvoie nil si le client ne dit rien (on cherche alors quand meme).
local function Trackers()
  if not (C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetTrackingInfo) then return nil end
  local active, finders, only, sawSpell = 0, 0, nil, false
  for i = 1, C_Minimap.GetNumTrackingTypes() do
    local info = C_Minimap.GetTrackingInfo(i)
    if IsSecret(info) then return nil end
    if info and info.spellID then sawSpell = true end
    if info and info.active then
      active = active + 1
      local kind = info.spellID and FINDERS[info.spellID]
      if kind then finders = finders + 1; only = kind end
    end
  end
  if not sawSpell then return nil end              -- le client ne donne pas les sorts de pistage : on cherche quand meme
  return active, finders, (active == 1 and finders == 1) and only or nil, (finders == 1) and only or nil
end

-- Position ---------------------------------------------------------------------------------------------
local function MapPosition()
  if not (C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition and C_Map.GetMapWorldSize) then return nil end
  local map = C_Map.GetBestMapForUnit("player")
  if not map then return nil end
  local pos = C_Map.GetPlayerMapPosition(map, "player")
  if not pos then return nil end
  local x, y = pos:GetXY()
  local w, h = C_Map.GetMapWorldSize(map)
  if not (x and y and w and h and w > 0 and h > 0) then return nil end
  return map, x, y, w, h
end

local function Rotating()
  return GetCVar("rotateMinimap") == "1" and GetPlayerFacing and GetPlayerFacing() ~= nil
end

-- Icones --------------------------------------------------------------------------------------------------
local markers = {}     -- { name, icon, map, mx, my (monde), ox, oy (minimap, repli), count }
local pool = {}
local RING = "Interface\\Minimap\\MiniMap-TrackingBorder"
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

-- Cadres tires de l'atlas du jeu : atlas, taille du cadre relativement a l'icone, taille de l'icone dans le cadre,
-- et rond (icone decoupee en cercle). Un atlas absent de ce client : l'icone s'affiche sans cadre.
MN.STYLES = {
  { id = "ring",   builtin = true },
  { id = "round",  builtin = true },
  { id = "square", builtin = true },
  { id = "createFrame", atlas = "character-create-icon-frame",        scale = 1.30, icon = 1.00 },
  { id = "createGlow",  atlas = "character-create-icon-selectedglow", scale = 1.60, icon = 1.00 },
  { id = "diamond",     atlas = "UI-Journeys-Delve-Level-Square",     scale = 1.80, icon = 0.62, behind = true },
  { id = "actionBar",   atlas = "UI-HUD-ActionBar-Frame",             scale = 1.25, icon = 1.00, behind = true },
  { id = "followerRing", atlas = "adventures-mission-follower-tutorial-ring", scale = 1.45, icon = 0.95, round = true },
}
local STYLE_BY_ID = {}
for _, st in ipairs(MN.STYLES) do STYLE_BY_ID[st.id] = st end

local function NewFrame()
  local f = CreateFrame("Frame", nil, Minimap)
  f:SetFrameLevel(Minimap:GetFrameLevel() + 6)
  f:EnableMouse(false)
  f.tex = f:CreateTexture(nil, "ARTWORK")
  f.tex:SetPoint("CENTER")
  f.frameTex = f:CreateTexture(nil, "OVERLAY")
  f.mask = f:CreateMaskTexture()
  f.mask:SetTexture(MASK, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  f.mask:SetAllPoints(f.tex)
  f.ring = f:CreateTexture(nil, "OVERLAY")
  f.ring:SetTexture(RING)
  pool[#pool + 1] = f
  return f
end

local function Style(f)
  local cfg = Cfg()
  local size = cfg.size or 14
  local style = cfg.style or "ring"
  local def = STYLE_BY_ID[style] or STYLE_BY_ID.ring
  f:SetSize(size, size)
  f.tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  f.frameTex:Hide()
  local iconSize = size * (def.icon or 1)
  f.tex:SetSize(iconSize, iconSize)
  if def.atlas then
    -- Cadre d'atlas (si ce client le connait)
    local known = not (C_Texture and C_Texture.GetAtlasInfo) or C_Texture.GetAtlasInfo(def.atlas) ~= nil
    if known then
      local fs = size * def.scale * ((cfg.frameScale or 100) / 100)
      -- "behind" : le cadre est un fond, derriere l'icone ; sinon il la recouvre
      f.frameTex:SetDrawLayer(def.behind and "BACKGROUND" or "OVERLAY")
      f.frameTex:SetAtlas(def.atlas)
      f.frameTex:SetSize(fs, fs)
      f.frameTex:ClearAllPoints()
      f.frameTex:SetPoint("CENTER", f, "CENTER")
      f.frameTex:Show()
    end
    if def.round then f.tex:AddMaskTexture(f.mask) else f.tex:RemoveMaskTexture(f.mask) end
    f.ring:Hide()
  elseif style == "square" then
    f.tex:RemoveMaskTexture(f.mask)
    f.ring:Hide()
  else
    f.tex:AddMaskTexture(f.mask)
    f.ring:SetShown(style == "ring")
    local k = size / 20
    f.ring:SetSize(50 * k, 50 * k)
    f.ring:ClearAllPoints()
    f.ring:SetPoint("CENTER", f, "CENTER", 9.5 * k, -10.5 * k)
  end
end

local function Show(i, m, ox, oy)
  local f = pool[i] or NewFrame()
  local stamp = (Cfg().size or 14) .. (Cfg().style or "ring") .. (Cfg().frameScale or 100)
  if f._styled ~= stamp then
    Style(f)
    f._styled = stamp
  end
  f.tex:SetTexture(m.icon)
  f:ClearAllPoints()
  f:SetPoint("CENTER", Minimap, "CENTER", ox, oy)
  f:Show()
end

local function HideFrom(i)
  for j = i, #pool do pool[j]:Hide() end
end

-- Place les icones : depuis la position actuelle (coordonnees du monde), sinon depuis le balayage
local lastKey
local function Follow(force)
  if not markers[1] then HideFrom(1); lastKey = nil; return end
  local map, px, py, ww, wh = MapPosition()
  local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
  local half = Minimap:GetWidth() / 2
  local facing = Rotating() and GetPlayerFacing() or 0
  local key = map and (map .. ":" .. px .. ":" .. py .. ":" .. tostring(radius) .. ":" .. facing) or "static"
  if not force and key == lastKey then return end
  lastKey = key
  local n = 0
  local sin, cos = math.sin(facing), math.cos(facing)
  for _, m in ipairs(markers) do
    local ox, oy
    if map and m.map == map and radius and not IsSecret(radius) and radius > 0 then
      local east, north = (m.mx - px) * ww, (py - m.my) * wh
      local k = half / radius                       -- unites de minimap par verge
      ox = (east * cos + north * sin) * k
      oy = (-east * sin + north * cos) * k
    elseif m.ox then
      ox, oy = m.ox, m.oy                            -- repli : la ou le balayage l'a vu
    end
    if ox and ox * ox + oy * oy <= (half - 2) ^ 2 then
      n = n + 1
      Show(n, m, ox, oy)
    end
  end
  HideFrom(n + 1)
end

-- Balayage -------------------------------------------------------------------------------------------------
local scan, grid, gridWidth
local nextScan = 0

local function BuildGrid(width)
  if gridWidth == width then return end
  gridWidth, grid = width, {}
  local half = width / 2
  for x = 0, width, STEP do
    for y = 0, width, STEP do
      local dx, dy = x - half, y - half
      if dx * dx + dy * dy <= half * half then grid[#grid + 1] = { x, y } end
    end
  end
end

local function Probe(left, bottom, scale, p, hits)
  Minimap:UpdateMouseoverAtPoint((left + p[1]) * scale, (bottom + p[2]) * scale)
  local d = MN._dbg
  d.probes = d.probes + 1
  local data = C_TooltipInfo.GetMinimapMouseover()
  if not data or IsSecret(data) then return end
  local lines = data.lines
  if not lines or IsSecret(lines) then return end
  -- Une ligne d'infobulle peut empiler plusieurs noms (un par point sous la souris, plus des objectifs de quete :
  -- "Mage royal\nFleur de serpent\n- Fleur de serpent : 0/10"). Chaque nom compte a part, sinon une plante
  -- superposee a un marqueur de quete est lue comme un seul "nom" et son endroit est decale.
  local seen = {}
  for _, line in ipairs(lines) do
    local raw = line.leftText
    if raw and not IsSecret(raw) then
      for chunk in Clean(raw):gmatch("[^\n]+") do
        local piece = chunk:gsub("^%s+", ""):gsub("%s+$", "")
        -- Objectifs de quete ("- Fleur de serpent : 0/10") et lignes chiffrees : pas des noms de points
        if piece ~= "" and not seen[piece] and not piece:find("^[%-%d]") and not piece:find(":") then
          seen[piece] = true
          d.withData = d.withData + 1
          d.names[piece] = (d.names[piece] or 0) + 1
          local h = hits[piece]
          if not h then h = {}; hits[piece] = h end
          h[#h + 1] = p
        end
      end
    end
  end
end

-- Points d'un meme nom -> endroits : groupes de proche en proche, puis un endroit par groupe (k-moyennes quand un
-- groupe est trop gros pour un seul point)
local function Cluster(points)
  local groups, left = {}, {}
  for i, p in ipairs(points) do left[i] = p end
  local link = STEP * 1.6
  while #left > 0 do
    local g = { table.remove(left) }
    local grew = true
    while grew do
      grew = false
      for i = #left, 1, -1 do
        local q = left[i]
        for _, p in ipairs(g) do
          local dx, dy = q[1] - p[1], q[2] - p[2]
          if dx * dx + dy * dy <= link * link then
            g[#g + 1] = table.remove(left, i)
            grew = true
            break
          end
        end
      end
    end
    groups[#groups + 1] = g
  end
  local places = {}
  for _, g in ipairs(groups) do
    local k = (#g > SINGLE_MAX) and math.ceil(#g / 7) or 1
    local centers = {}
    if k == 1 then
      local sx, sy = 0, 0
      for _, p in ipairs(g) do sx, sy = sx + p[1], sy + p[2] end
      centers[1] = { sx / #g, sy / #g, #g }
    else
      -- centres de depart : le plus eloigne de ceux deja pris
      centers[1] = { g[1][1], g[1][2] }
      while #centers < k do
        local best, bd = nil, -1
        for _, p in ipairs(g) do
          local d = math.huge
          for _, c in ipairs(centers) do d = math.min(d, (p[1] - c[1]) ^ 2 + (p[2] - c[2]) ^ 2) end
          if d > bd then best, bd = p, d end
        end
        centers[#centers + 1] = { best[1], best[2], #g / k }
      end
      for _ = 1, 6 do
        local sums = {}
        for i = 1, k do sums[i] = { 0, 0, 0 } end
        for _, p in ipairs(g) do
          local bi, bd = 1, math.huge
          for i, c in ipairs(centers) do
            local d = (p[1] - c[1]) ^ 2 + (p[2] - c[2]) ^ 2
            if d < bd then bi, bd = i, d end
          end
          local s = sums[bi]
          s[1], s[2], s[3] = s[1] + p[1], s[2] + p[2], s[3] + 1
        end
        for i, c in ipairs(centers) do
          local s = sums[i]
          if s[3] > 0 then c[1], c[2] = s[1] / s[3], s[2] / s[3] end
        end
      end
    end
    for _, c in ipairs(centers) do places[#places + 1] = c end
  end
  return places
end

-- Memoire des noeuds : le jeu ne dit de quelle plante il s'agit qu'a une dizaine de metres ("???" au-dela). Un noeud
-- identifie de pres est donc retenu (carte + position, identifiant d'objet : independant de la langue) ; plus tard, un
-- point "???" au meme endroit prend son icone. Commun a tous les personnages et profils (racine des SavedVariables).
local ITEM_KIND = {}
for _, id in ipairs(HERB_ITEMS) do ITEM_KIND[id] = "herbs" end
for _, id in ipairs(ORE_ITEMS) do ITEM_KIND[id] = "ore" end
local MEMORY_MERGE = 8     -- verges : deux repères plus proches que ca ne font qu'un

local function Memory(map)
  if type(AishaddonDB) ~= "table" then return nil end
  AishaddonDB.minimapNodesKnown = AishaddonDB.minimapNodesKnown or {}
  local all = AishaddonDB.minimapNodesKnown
  all[map] = all[map] or {}
  return all[map]
end

local function Remember(map, mx, my, ww, wh, id)
  local list = Memory(map)
  if not list then return end
  for _, e in ipairs(list) do
    local dx, dy = (e[1] - mx) * ww, (e[2] - my) * wh
    if dx * dx + dy * dy <= MEMORY_MERGE * MEMORY_MERGE then
      e[3] = id                              -- meme endroit : l'identification fraiche prime
      return
    end
  end
  list[#list + 1] = { mx, my, id }
end

local function Recall(map, mx, my, ww, wh)
  local list = Memory(map)
  if not list then return nil end
  local best, bd = nil, (MEMORY_MERGE * 1.6) ^ 2
  for _, e in ipairs(list) do
    local dx, dy = (e[1] - mx) * ww, (e[2] - my) * wh
    local d = dx * dx + dy * dy
    if d <= bd then best, bd = e[3], d end
  end
  return best
end

-- Un balayage termine : les endroits trouves deviennent des repères du monde, fondus avec ceux deja connus
local function Finish(hits, only, finderKind)
  local width = Minimap:GetWidth()
  local half = width / 2
  local map, px, py, ww, wh = MapPosition()
  local radius = C_Minimap and C_Minimap.GetViewRadius and C_Minimap.GetViewRadius()
  if IsSecret(radius) then radius = nil end
  local facing = Rotating() and GetPlayerFacing() or 0
  local sin, cos = math.sin(facing), math.cos(facing)

  local found = {}
  for name, points in pairs(hits) do
    local kind, icon, id = Resolve(name, only, finderKind)
    if kind then
      for _, c in ipairs(Cluster(points)) do
       -- Un seul point de grille qui repond n'est pas un vrai point de minimap (un vrai en donne 4 a 9) : bruit,
       -- sinon l'icone apparait une ou deux secondes puis disparait
       if (c[3] or 2) >= 2 then
        local ox, oy = c[1] - half, c[2] - half
        local m = { name = name, kind = kind, icon = icon, ox = ox, oy = oy, count = 1 }
        if map and radius and radius > 0 then
          local k = radius / half                      -- verges par unite de minimap
          local east = (ox * cos - oy * sin) * k
          local north = (ox * sin + oy * cos) * k
          m.map, m.mx, m.my = map, px + east / ww, py - north / wh
          if id then
            Remember(map, m.mx, m.my, ww, wh, id)    -- identifie de pres : retenu pour la prochaine fois
          else
            -- Non identifie (point "???" ou repli generique) : un noeud deja identifie ici donne son icone
            local known = Recall(map, m.mx, m.my, ww, wh)
            if known and ITEM_KIND[known] then
              m.kind, m.icon = ITEM_KIND[known], ItemIcon(known)
            end
          end
        end
        found[#found + 1] = m
       end
      end
    end
  end

  -- Fusion : un endroit revu (meme nom, a moins de MERGE verges) garde sa place, ramenee vers la nouvelle
  -- mesure ; un endroit qui n'est plus vu disparait
  for _, m in ipairs(found) do
    if m.map then
      for _, old in ipairs(markers) do
        if old.map == m.map and old.name == m.name and not old._used then
          local dx, dy = (old.mx - m.mx) * ww, (old.my - m.my) * wh
          if dx * dx + dy * dy <= MERGE * MERGE then
            old._used = true
            local n = math.min(old.count or 1, 8)
            m.mx = old.mx + (m.mx - old.mx) / (n + 1)
            m.my = old.my + (m.my - old.my) / (n + 1)
            m.count = n + 1
            break
          end
        end
      end
    end
  end
  for _, old in ipairs(markers) do
    if not old._used and old.map == map and (old.miss or 0) < 1 then
      old.miss = (old.miss or 0) + 1
      found[#found + 1] = old
    end
    old._used = nil
  end
  for _, m in ipairs(found) do
    if m.miss == nil then m.miss = 0 end
  end
  markers = found
  MN._dbg.found = #found
  MN._dbg.scans = MN._dbg.scans + 1
  Follow(true)
end

local function ScanSome()
  local left, bottom = Minimap:GetLeft(), Minimap:GetBottom()
  if not (left and bottom and Minimap:IsVisible()) or InCombatLockdown() then
    scan = nil
    return
  end
  local scale = Minimap:GetEffectiveScale()
  Minimap:SetUsingSoftCursor(true)
  local stop = math.min(scan.next + PER_FRAME - 1, #grid)
  for i = scan.next, stop do Probe(left, bottom, scale, grid[i], scan.hits) end
  Minimap:SetUsingSoftCursor(false)
  scan.next = stop + 1
  if scan.next > #grid then
    local hits, only, finderKind = scan.hits, scan.only, scan.finderKind
    scan = nil
    nextScan = GetTime() + SCAN_WAIT
    Finish(hits, only, finderKind)
  end
end

local function StartScan()
  local cfg = Cfg()
  nextScan = GetTime() + IDLE_WAIT
  if cfg.enabled ~= true or InCombatLockdown() or not Minimap:IsVisible() or not Minimap:GetLeft() then
    if markers[1] then markers = {}; Follow(true) end
    return
  end
  local active, finders, only, finderKind = Trackers()
  if active == 0 then                            -- aucun pistage actif : rien a chercher
    if markers[1] then markers = {}; Follow(true) end
    return
  end
  if indexMissing then BuildIndex() end
  BuildGrid(Minimap:GetWidth())
  scan = { next = 1, hits = {}, only = only, finderKind = finderKind }
  nextScan = 0
end

local driver = CreateFrame("Frame")
local accum = 0
local function Step(el)
  if scan then
    ScanSome()
  elseif GetTime() >= nextScan then
    StartScan()
  end
  accum = accum + el
  if accum >= 0.03 then
    accum = 0
    Follow()
  end
end
local function OnUpdate(_, el)
  local ok, err = pcall(Step, el)
  if not ok then
    MN._err = tostring(err)
    scan = nil
    nextScan = GetTime() + 5          -- une erreur ne doit pas se rejouer a chaque image
  end
end

function MN.ApplySettings()
  local cfg = Cfg()
  if cfg.enabled == true and MN.Available() then
    driver:SetScript("OnUpdate", OnUpdate)
    for _, f in ipairs(pool) do f._styled = nil end
    if Minimap.SetIconScale then Minimap:SetIconScale((cfg.dotScale or 100) / 100) end
    lastKey = nil
    nextScan = 0
  else
    driver:SetScript("OnUpdate", nil)
    scan, markers = nil, {}
    HideFrom(1)
    if Minimap and Minimap.SetIconScale then Minimap:SetIconScale(1) end
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("GET_ITEM_INFO_RECEIVED")
ev:RegisterEvent("MINIMAP_UPDATE_TRACKING")
ev:RegisterEvent("MINIMAP_UPDATE_ZOOM")
ev:SetScript("OnEvent", function(_, event)
  if event == "GET_ITEM_INFO_RECEIVED" then
    if indexMissing then BuildIndex() end
  elseif event == "PLAYER_ENTERING_WORLD" then
    markers = {}
    MN.ApplySettings()
  else
    nextScan = 0        -- pistage ou zoom change : balayer tout de suite
    lastKey = nil
  end
end)

-- /aishnodes : etat du balayage (a donner en cas de souci)
SLASH_AISHNODES1 = "/aishnodes"
SlashCmdList["AISHNODES"] = function()
  local P = "|cff00ffff[AishCore]|r "
  local cfg = Cfg()
  local miss = MN.Missing()
  if #miss > 0 then print(P .. "Nodes : appels absents de ce client : " .. table.concat(miss, ", ")) end
  print(P .. "Nodes : disponible=" .. tostring(MN.Available()) .. " active=" .. tostring(cfg.enabled)
    .. " balayage=" .. tostring(driver:GetScript("OnUpdate") ~= nil) .. " erreur=" .. tostring(MN._err))
  print(P .. "index : " .. #index .. " noms (manquants=" .. tostring(indexMissing) .. ")  grille=" .. tostring(grid and #grid))
  local n = C_Minimap and C_Minimap.GetNumTrackingTypes and C_Minimap.GetNumTrackingTypes() or 0
  for i = 1, n do
    local info = C_Minimap.GetTrackingInfo(i)
    if info and info.active then print(P .. "pistage actif : " .. tostring(info.name) .. " spellID=" .. tostring(info.spellID)) end
  end
  local d = MN._dbg
  local mem = 0
  for _, list in pairs((type(AishaddonDB) == "table" and AishaddonDB.minimapNodesKnown) or {}) do mem = mem + #list end
  print(P .. "noeuds memorises : " .. mem)
  print(P .. "dernier balayage : points=" .. d.probes .. " reponses=" .. d.withData .. " endroits=" .. d.found
    .. " balayages=" .. d.scans .. "  icones affichees=" .. (function() local c = 0 for _, f in ipairs(pool) do if f:IsShown() then c = c + 1 end end return c end)())
  local shown = 0
  for name, c in pairs(d.names) do
    if shown < 8 then
      print(P .. "  nom lu : " .. name .. " x" .. c .. " -> " .. tostring(Resolve(name, nil) or "?"))
      local hex = {}
      for i = 1, math.min(#name, 10) do hex[#hex + 1] = string.format("%02x", name:byte(i)) end
      print(P .. "     octets=" .. table.concat(hex, " ") .. " longueur=" .. #name .. " nettoye=[" .. Plain(name) .. "]")
      print(P .. "     " .. tostring(d.sample[name]))
      shown = shown + 1
    end
  end
  local loaded = {}
  for _, e in ipairs(index) do loaded[#loaded + 1] = e.key end
  print(P .. "noms connus : " .. table.concat(loaded, ", "))
  -- Remise a zero : le prochain balayage remplit des chiffres frais
  d.probes, d.withData, d.names, d.sample = 0, 0, {}, {}
  nextScan = 0
end

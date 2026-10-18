-- Modules/MapReveal.lua : "Reveler la carte" (QoL). Affiche sur la carte du monde les zones pas encore decouvertes,
-- au lieu du fond vide : le jeu ne dessine que les calques explores (C_MapExplorationInfo.GetExploredMapTextures),
-- on ajoute les autres d'apres Data/MapOverlays.lua (tables du client). Option : les teinter (brouillard colore)
-- pour distinguer ce qui reste a explorer. Les calques ajoutes vivent sur le pin d'exploration du jeu, a la suite
-- de son propre rafraichissement (hooksecurefunc, jamais de remplacement de fonction Blizzard).
-- Reglages : ns.DB.comfort.mapReveal / mapRevealColored / mapRevealColor.
local addonName, ns = ...

local MapReveal = {}
ns.Modules.MapReveal = MapReveal

local hookedPins = {}
local cache = {}   -- artID -> liste de calques decodes

local function Cfg() return ns.GetCfg("comfort") or {} end

-- "w,h,x,y,fid:fid;..." -> { { w, h, x, y, { fid, ... } }, ... }
local function Overlays(artID)
  local c = cache[artID]
  if c then return c end
  local raw = ns.MapOverlays and ns.MapOverlays[artID]
  if not raw then return nil end
  c = {}
  for block in raw:gmatch("[^;]+") do
    local w, h, x, y, fids = block:match("^(%d+),(%d+),(%d+),(%d+),(.+)$")
    if w then
      local list = {}
      for f in fids:gmatch("%d+") do list[#list + 1] = tonumber(f) end
      c[#c + 1] = { tonumber(w), tonumber(h), tonumber(x), tonumber(y), list }
    end
  end
  cache[artID] = c
  return c
end

local function ReleaseAll(pin)
  for _, t in ipairs(pin._aishReveal or {}) do t:Hide() end
  pin._aishRevealUsed = 0
end

local function Acquire(pin)
  pin._aishReveal = pin._aishReveal or {}
  pin._aishRevealUsed = (pin._aishRevealUsed or 0) + 1
  local t = pin._aishReveal[pin._aishRevealUsed]
  if not t then
    t = pin:CreateTexture(nil, "ARTWORK", nil, -1)
    pin._aishReveal[pin._aishRevealUsed] = t
  end
  return t
end

-- Meme decoupe en tuiles que le jeu (MapExplorationPinMixin:RefreshOverlays) : la derniere tuile d'une ligne / colonne
-- est plus petite, son fichier fait la puissance de 2 superieure (d'ou le TexCoord partiel).
local function FileSize(px)
  local s = 16
  while s < px do s = s * 2 end
  return s
end

local function Draw(pin)
  ReleaseAll(pin)
  local c = Cfg()
  if not c.mapReveal then return end
  local map = pin.GetMap and pin:GetMap()
  local mapID = map and map.GetMapID and map:GetMapID()
  if not mapID then return end
  local artID = C_Map.GetMapArtID and C_Map.GetMapArtID(mapID)
  local list = artID and Overlays(artID)
  if not list then return end

  local explored = {}
  local ok, exp = pcall(C_MapExplorationInfo.GetExploredMapTextures, mapID)
  for _, e in ipairs(ok and exp or {}) do explored[e.offsetX .. ":" .. e.offsetY] = true end

  local tileW, tileH = 256, 256
  local layers = C_Map.GetMapArtLayers and C_Map.GetMapArtLayers(mapID)
  local layerIndex = map.GetCanvasContainer and map:GetCanvasContainer().GetCurrentLayerIndex
    and map:GetCanvasContainer():GetCurrentLayerIndex() or 1
  local li = layers and layers[layerIndex]
  if li then tileW, tileH = li.tileWidth or tileW, li.tileHeight or tileH end

  local col = c.mapRevealColored and (c.mapRevealColor or { 0.35, 0.6, 0.95, 1 }) or nil
  for _, o in ipairs(list) do
    local w, h, x, y, fids = o[1], o[2], o[3], o[4], o[5]
    if not explored[x .. ":" .. y] then
      local wide, tall = math.ceil(w / tileW), math.ceil(h / tileH)
      for j = 1, tall do
        local ph = (j < tall) and tileH or ((h % tileH == 0) and tileH or h % tileH)
        local fh = (j < tall) and tileH or FileSize(ph)
        for k = 1, wide do
          local fid = fids[(j - 1) * wide + k]
          if fid then
            local pw = (k < wide) and tileW or ((w % tileW == 0) and tileW or w % tileW)
            local fw = (k < wide) and tileW or FileSize(pw)
            local t = Acquire(pin)
            t:ClearAllPoints()
            t:SetSize(pw, ph)
            t:SetTexCoord(0, pw / fw, 0, ph / fh)
            t:SetPoint("TOPLEFT", pin, "TOPLEFT", x + tileW * (k - 1), -(y + tileH * (j - 1)))
            t:SetTexture(fid, nil, nil, "TRILINEAR")
            if col then t:SetVertexColor(col[1], col[2], col[3], col[4] or 1) else t:SetVertexColor(1, 1, 1, 1) end
            t:Show()
          end
        end
      end
    end
  end
end

local function HookPin(pin)
  if hookedPins[pin] or not pin.RefreshOverlays then return end
  hookedPins[pin] = true
  hooksecurefunc(pin, "RefreshOverlays", function(self) pcall(Draw, self) end)
end

local function HookMap()
  local wm = _G.WorldMapFrame
  if not (wm and wm.EnumeratePinsByTemplate) then return false end
  for pin in wm:EnumeratePinsByTemplate("MapExplorationPinTemplate") do HookPin(pin) end
  -- Pins crees plus tard (premier affichage de la carte) : accroches a leur acquisition
  if not wm._aishRevealHooked and wm.AcquirePin then
    wm._aishRevealHooked = true
    hooksecurefunc(wm, "AcquirePin", function(self, template)
      if template == "MapExplorationPinTemplate" then
        for pin in self:EnumeratePinsByTemplate("MapExplorationPinTemplate") do HookPin(pin) end
      end
    end)
  end
  return true
end

-- Applique un changement de reglage a la carte ouverte
function MapReveal.ApplySettings()
  if not HookMap() then return end
  for pin in pairs(hookedPins) do
    if pin.RefreshOverlays then pcall(pin.RefreshOverlays, pin, true) end
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("ADDON_LOADED")
ev:SetScript("OnEvent", function(_, event, name)
  if event == "PLAYER_LOGIN" or name == "Blizzard_WorldMap" then HookMap() end
end)

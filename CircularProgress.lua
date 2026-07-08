-- CircularProgress.lua : Moteur de rendu circulaire (port de WeakAuras)
local addonName, ns = ...

-- TextureCoords : gestion des coordonnées de texture pour le rendu circulaire
local TextureCoords = {}
do
  local defaultTexCoord = {
    ULx = 0, ULy = 0,
    LLx = 0, LLy = 1,
    URx = 1, URy = 0,
    LRx = 1, LRy = 1,
  }

  local exactAngles = {
    {0.5, 0}, {1, 0}, {1, 0.5}, {1, 1}, {0.5, 1}, {0, 1}, {0, 0.5}, {0, 0}
  }

  local function angleToCoord(angle)
    angle = angle % 360
    if (angle % 45 == 0) then
      local index = math.floor(angle / 45) + 1
      return exactAngles[index][1], exactAngles[index][2]
    end
    if (angle < 45) then
      return 0.5 + math.tan(math.rad(angle)) / 2, 0
    elseif (angle < 135) then
      return 1, 0.5 + math.tan(math.rad(angle - 90)) / 2
    elseif (angle < 225) then
      return 0.5 - math.tan(math.rad(angle)) / 2, 1
    elseif (angle < 315) then
      return 0, 0.5 - math.tan(math.rad(angle - 90)) / 2
    else
      return 0.5 + math.tan(math.rad(angle)) / 2, 0
    end
  end

  local function TransformPoint(x, y, scalex, scaley, texRotation, mirror_h, mirror_v, user_x, user_y)
    x = x - 0.5; y = y - 0.5
    x = x * 1.4142; y = y * 1.4142
    x = x / (scalex or 1); y = y / (scaley or 1)
    if mirror_h then x = -x end
    if mirror_v then y = -y end
    local cos_r = math.cos(texRotation or 0)
    local sin_r = math.sin(texRotation or 0)
    x, y = cos_r * x - sin_r * y, sin_r * x + cos_r * y
    x = x + 0.5; y = y + 0.5
    x = x + (user_x or 0); y = y + (user_y or 0)
    return x, y
  end

  local funcs = {}
  funcs.Hide = function(self) self.texture:Hide() end
  funcs.Show = function(self) self:Apply(); self.texture:Show() end
  funcs.SetFull = function(self)
    self.ULx, self.ULy = 0,0; self.LLx, self.LLy = 0,1; self.URx, self.URy = 1,0; self.LRx, self.LRy = 1,1
    self.ULvx, self.ULvy, self.LLvx, self.LLvy, self.URvx, self.URvy, self.LRvx, self.LRvy = 0,0,0,0,0,0,0,0
  end
  funcs.Apply = function(self)
    pcall(function()
      self.texture:SetVertexOffset(UPPER_RIGHT_VERTEX, self.URvx, self.URvy)
      self.texture:SetVertexOffset(UPPER_LEFT_VERTEX, self.ULvx, self.ULvy)
      self.texture:SetVertexOffset(LOWER_RIGHT_VERTEX, self.LRvx, self.LRvy)
      self.texture:SetVertexOffset(LOWER_LEFT_VERTEX, self.LLvx, self.LLvy)
      self.texture:SetTexCoord(self.ULx, self.ULy, self.LLx, self.LLy, self.URx, self.URy, self.LRx, self.LRy)
    end)
  end
  funcs.MoveCorner = function(self, width, height, corner, x, y)
    local rx = defaultTexCoord[corner .. "x"] - x
    local ry = defaultTexCoord[corner .. "y"] - y
    self[corner .. "vx"] = -rx * width
    self[corner .. "vy"] = ry * height
    self[corner .. "x"] = x; self[corner .. "y"] = y
  end
  funcs.SetAngle = function(self, width, height, angle1, angle2)
    local index = math.floor((angle1 + 45) / 90)
    local pointOrder = { "LL", "UL", "UR", "LR", "LL", "UL", "UR", "LR", "LL", "UL", "UR", "LR" }
    local middleCorner = pointOrder[index + 1]
    local startCorner = pointOrder[index + 2]
    local endCorner1 = pointOrder[index + 3]
    local endCorner2 = pointOrder[index + 4]
    self:MoveCorner(width, height, middleCorner, 0.5, 0.5)
    local sx, sy = angleToCoord(angle1)
    self:MoveCorner(width, height, startCorner, sx, sy)
    local edge1 = math.floor((angle1 - 45) / 90)
    local edge2 = math.floor((angle2 - 45) / 90)
    if (edge1 == edge2) then
      local ex, ey = angleToCoord(angle2)
      self:MoveCorner(width, height, endCorner1, ex, ey)
    else
      self:MoveCorner(width, height, endCorner1, defaultTexCoord[endCorner1 .. "x"], defaultTexCoord[endCorner1 .. "y"])
    end
    local ex2, ey2 = angleToCoord(angle2)
    self:MoveCorner(width, height, endCorner2, ex2, ey2)
  end
  funcs.Transform = function(self, scalex, scaley, texRotation, mirror_h, mirror_v, user_x, user_y)
    self.ULx, self.ULy = TransformPoint(self.ULx, self.ULy, scalex, scaley, texRotation, mirror_h, mirror_v, user_x, user_y)
    self.LLx, self.LLy = TransformPoint(self.LLx, self.LLy, scalex, scaley, texRotation, mirror_h, mirror_v, user_x, user_y)
    self.URx, self.URy = TransformPoint(self.URx, self.URy, scalex, scaley, texRotation, mirror_h, mirror_v, user_x, user_y)
    self.LRx, self.LRy = TransformPoint(self.LRx, self.LRy, scalex, scaley, texRotation, mirror_h, mirror_v, user_x, user_y)
  end

  function TextureCoords.create(texture)
    local coord = {
      ULx = 0, ULy = 0, LLx = 0, LLy = 1, URx = 1, URy = 0, LRx = 1, LRy = 1,
      ULvx = 0, ULvy = 0, LLvx = 0, LLvy = 0, URvx = 0, URvy = 0, LRvx = 0, LRvy = 0,
      texture = texture
    }
    for k, f in pairs(funcs) do coord[k] = f end
    return coord
  end
end

-- CircularProgress : gestion de l'affichage en arc
local CircularProgress = {}
do
  local funcs = {}
  funcs.SetRotation = function(self, radians)
    for i = 1, 3 do if self.textures[i].SetRotation then self.textures[i]:SetRotation(radians) end end
  end
  funcs.SetTextureOrAtlas = function(self, texture)
    for i = 1, 3 do pcall(function() self.textures[i]:SetTexture(texture) end) end
  end
  funcs.SetDesaturated = function(self, d) for i=1,3 do if self.textures[i].SetDesaturated then self.textures[i]:SetDesaturated(d) end end end
  funcs.SetBlendMode = function(self, m) for i=1,3 do pcall(function() self.textures[i]:SetBlendMode(m) end) end end
  funcs.Show = function(self) self.visible = true; for i=1,3 do self.textures[i]:Show() end end
  funcs.Hide = function(self) self.visible = false; for i=1,3 do self.textures[i]:Hide() end end
  funcs.SetColor = function(self, r,g,b,a) for i=1,3 do pcall(function() self.textures[i]:SetVertexColor(r,g,b,a) end) end end
  funcs.SetCropX = function(self, x) self.crop_x = x; self:UpdateTextures() end
  funcs.SetCropY = function(self, y) self.crop_y = y; self:UpdateTextures() end
  funcs.SetTexRotation = function(self, tr) self.texRotation = tr; self:UpdateTextures() end
  funcs.SetMirror = function(self, m) self.mirror = m; self:UpdateTextures() end
  funcs.SetScale = function(self, sx, sy) self.scalex, self.scaley = sx, sy end
  funcs.SetWidth = function(self, w) self.width = w end
  funcs.SetHeight = function(self, h) self.height = h end

  funcs.UpdateTextures = function(self)
    if not self.visible then return end
    local crop_x = self.crop_x or 1
    local crop_y = self.crop_y or 1
    local texRotation = self.texRotation or 0
    local mirror_h = self.mirror_h or false
    if self.mirror then mirror_h = not mirror_h end
    local mirror_v = self.mirror_v or false
    local width = self.width * (self.scalex or 1) + 2 * (self.offset or 0)
    local height = self.height * (self.scaley or 1) + 2 * (self.offset or 0)
    if width == 0 or height == 0 then return end
    local angle1 = self.angle1
    local angle2 = self.angle2
    if angle1 == nil or angle2 == nil then return end
    if (angle2 - angle1 >= 360) then
      self.coords[1]:SetFull(); self.coords[1]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v); self.coords[1]:Show()
      self.coords[2]:Hide(); self.coords[3]:Hide(); return
    end
    if angle1 == angle2 then self.coords[1]:Hide(); self.coords[2]:Hide(); self.coords[3]:Hide(); return end
    local index1 = math.floor((angle1 + 45) / 90)
    local index2 = math.floor((angle2 + 45) / 90)
    if (index1 + 1 >= index2) then
      self.coords[1]:SetAngle(width, height, angle1, angle2); self.coords[1]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v); self.coords[1]:Show(); self.coords[2]:Hide(); self.coords[3]:Hide()
    elseif (index1 + 3 >= index2) then
      local firstEnd = (index1 + 1) * 90 + 45
      self.coords[1]:SetAngle(width, height, angle1, firstEnd); self.coords[1]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v); self.coords[1]:Show()
      self.coords[2]:SetAngle(width, height, firstEnd, angle2); self.coords[2]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v); self.coords[2]:Show(); self.coords[3]:Hide()
    else
      local firstEnd = (index1 + 1) * 90 + 45
      local secondEnd = firstEnd + 180
      self.coords[1]:SetAngle(width, height, angle1, firstEnd); self.coords[1]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v); self.coords[1]:Show()
      self.coords[2]:SetAngle(width, height, firstEnd, secondEnd); self.coords[2]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v); self.coords[2]:Show()
      self.coords[3]:SetAngle(width, height, secondEnd, angle2); self.coords[3]:Transform(crop_x, crop_y, texRotation, mirror_h, mirror_v); self.coords[3]:Show()
    end
  end

  funcs.SetProgress = function(self, a1, a2)
    self.angle1 = a1; self.angle2 = a2; self:UpdateTextures()
  end

  function CircularProgress.create(frame, layer, drawLayer)
    local c = { textures = {}, coords = {}, offset = 0, visible = true }
    for i = 1, 3 do
      local t = frame:CreateTexture(nil, layer)
      t:SetSnapToPixelGrid(false)
      t:SetTexelSnappingBias(0)
      pcall(function() t:SetDrawLayer(layer, drawLayer) end)
      t:SetAllPoints(frame)
      c.textures[i] = t
      c.coords[i] = TextureCoords.create(t)
    end
    for k, f in pairs(funcs) do c[k] = f end
    c.parentFrame = frame
    return c
  end

  function CircularProgress.modify(c, options)
    c:SetTextureOrAtlas(options.texture)
    c:SetDesaturated(options.desaturated)
    c:SetBlendMode(options.blendMode)
    c:SetRotation(options.auraRotation or 0)
    c.crop_x = options.crop_x
    c.crop_y = options.crop_y
    c.mirror = options.mirror
    c.texRotation = options.texRotation
    c.width = options.width
    c.height = options.height
    c.offset = options.offset or 0
    if c.offset > 0 then
      for i = 1, 3 do
        c.textures[i]:ClearAllPoints()
        c.textures[i]:SetPoint('TOPRIGHT', c.parentFrame, c.offset, c.offset)
        c.textures[i]:SetPoint('BOTTOMRIGHT', c.parentFrame, c.offset, -c.offset)
        c.textures[i]:SetPoint('BOTTOMLEFT', c.parentFrame, -c.offset, -c.offset)
        c.textures[i]:SetPoint('TOPLEFT', c.parentFrame, -c.offset, c.offset)
      end
    else
      for i = 1, 3 do c.textures[i]:ClearAllPoints(); c.textures[i]:SetAllPoints(c.parentFrame) end
    end
    c:UpdateTextures()
  end
end

-- Exporter dans le namespace
ns.TextureCoords = TextureCoords
ns.CircularProgress = CircularProgress

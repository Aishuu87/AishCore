-- MemTrace.lua : /aishmem trace (Forever seulement), memoire allouee par chaque source d'execution d'AishCore.
-- Charge avant Core.lua : chaque OnUpdate / OnEvent pose par AishCore est enveloppe (crochet securise sur SetScript,
-- donc sans taint) et etiquete par son fichier:ligne. Pendant la mesure (10 s, ramasse-miettes arrete pour des
-- chiffres exacts), C_Timer.After est aussi enveloppe, comme /aishdebug (timers rearmes) ; les tickers passent par
-- ns.NewTicker, enveloppes des leur creation.
local addonName, ns = ...
-- Tickers d'AishCore : ns.NewTicker (Retail : C_Timer.NewTicker tel quel ; Forever : suivi par la trace, voir plus bas)
ns.NewTicker = C_Timer.NewTicker
if select(4, GetBuildInfo()) >= 20000 then return end

local T = { on = false, acc = {}, cnt = {} }
ns._memTrace = T

local count = collectgarbage
local cache = setmetatable({}, { __mode = "k" })     -- handler -> enveloppe
local foreign = setmetatable({}, { __mode = "k" })   -- handlers d'autres addons / Blizzard
local wrappers = setmetatable({}, { __mode = "k" })  -- nos enveloppes

-- Premier fichier:ligne d'AishCore dans la pile (hors ce fichier)
local function Site()
  local ok, s = pcall(debugstack, 3, 8, 0)
  -- Pile secrete (appel venu d'un contexte protege) : illisible, le handler est traite comme etranger
  if not ok or type(s) ~= "string" or (issecretvalue and issecretvalue(s)) then return nil end
  for line in s:gmatch("[^\n]+") do
    if not line:find("MemTrace", 1, true) then
      local file, n = line:match("AddOns[\\/]" .. addonName .. "[\\/]([^:\"]-)%.lua\"?%]?:(%d+)")
      if file then return file:gsub("^Modules[\\/]", "") .. ":" .. n end
    end
  end
end

local function Wrap(key, fn)
  local w = function(...)
    if not T.on then return fn(...) end
    local m0 = count("count")
    fn(...)
    T.acc[key] = (T.acc[key] or 0) + (count("count") - m0)
    T.cnt[key] = (T.cnt[key] or 0) + 1
  end
  wrappers[w] = true
  return w
end

local SCRIPTS = { OnUpdate = true, OnEvent = true }
local function OnSetScript(self, script, handler)
  if not SCRIPTS[script] or type(handler) ~= "function" or wrappers[handler] or foreign[handler] then return end
  local w = cache[handler]
  if not w then
    local key = Site()
    if not key then foreign[handler] = true; return end
    w = Wrap(script .. " " .. key, handler)
    cache[handler] = w
  end
  self:SetScript(script, w)
end

-- Pas d'EditBox : creee, elle prend le focus clavier (autoFocus) et bloque le clavier du jeu
for _, kind in ipairs({ "Frame", "Button", "CheckButton", "StatusBar", "Slider", "ScrollFrame",
                        "Cooldown", "PlayerModel", "Model", "ModelScene", "SimpleHTML", "MessageFrame", "GameTooltip" }) do
  pcall(function()
    local f = CreateFrame(kind)
    f:Hide()
    local mt = getmetatable(f)
    local idx = mt and mt.__index
    if type(idx) == "table" and not T[idx] then
      T[idx] = true
      hooksecurefunc(idx, "SetScript", OnSetScript)
    end
  end)
end

local function TimerArg(fn, label)
  if type(fn) ~= "function" or wrappers[fn] then return fn end
  local key = Site()
  if not key then return fn end
  return Wrap(label .. " " .. key, fn)
end

-- Ticker cree par AishCore (permanent compris) : enveloppe des sa creation, mesure seulement pendant la trace
ns.NewTicker = function(d, fn, n) return C_Timer.NewTicker(d, TimerArg(fn, "Ticker"), n) end

local P = "|cff33ff99[AishCore mem]|r "

function T.Run()
  if T.on then return end
  local origAfter, origTicker = C_Timer.After, C_Timer.NewTicker
  C_Timer.After = function(d, fn) return origAfter(d, TimerArg(fn, "After")) end
  C_Timer.NewTicker = function(d, fn, n) return origTicker(d, TimerArg(fn, "Ticker"), n) end
  wipe(T.acc); wipe(T.cnt)
  count("collect")
  count("stop")
  UpdateAddOnMemoryUsage()
  local m0, t0 = GetAddOnMemoryUsage(addonName), GetTime()
  T.on = true
  print(P .. "trace : 10 s, sans combat ni GUI ouvert de preference...")
  origAfter(10, function()
    T.on = false
    C_Timer.After, C_Timer.NewTicker = origAfter, origTicker
    UpdateAddOnMemoryUsage()
    local total = GetAddOnMemoryUsage(addonName) - m0
    count("restart")
    local dt = GetTime() - t0
    local rows, sum = {}, 0
    for key, kb in pairs(T.acc) do
      sum = sum + kb
      if kb > 0.05 then rows[#rows + 1] = { key = key, kb = kb, n = T.cnt[key] } end
    end
    table.sort(rows, function(a, b) return a.kb > b.kb end)
    print(P .. string.format("total AishCore : %.1f Ko/s | attribue : %.1f Ko/s | non attribue : %.1f Ko/s",
      total / dt, sum / dt, (total - sum) / dt))
    for i = 1, math.min(20, #rows) do
      local r = rows[i]
      print(P .. string.format("%-52s %7.1f Ko/s  (%d appels, %.0f o/appel)", r.key, r.kb / dt, r.n, r.kb * 1024 / r.n))
    end
  end)
end

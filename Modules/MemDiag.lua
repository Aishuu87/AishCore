-- Modules/MemDiag.lua : /aishmem, diagnostic memoire d'AishCore.
-- 1) memoire affichee (garbage compris) puis memoire vivante apres un collect complet ;
-- 2) poids estime des bases sauvegardees et des grosses tables de donnees ;
-- 3) debit de garbage (Ko/s) mesure sur 10 s apres le collect : un debit eleve fait gonfler la memoire
--    affichee entre deux passages du ramasse-miettes.
local addonName, ns = ...

local P = "|cff33ff99[AishCore mem]|r "

-- Estimation Lua 5.1 64 bits : table 56 o + 40 o par entree, chaine 25 o + longueur
local function Size(v, seen)
  local tv = type(v)
  if tv == "string" then return 25 + #v end
  if tv ~= "table" then return 0 end
  if seen[v] then return 0 end
  seen[v] = true
  local s = 56
  for k, x in pairs(v) do s = s + 40 + Size(k, seen) + Size(x, seen) end
  return s
end

local function KB(n) return string.format("%.0f Ko", n / 1024) end

local function AddonMem()
  UpdateAddOnMemoryUsage()
  return GetAddOnMemoryUsage(addonName) or 0   -- deja en Ko
end

-- Les plus gros sous-blocs d'une table (n premiers, au-dessus de minBytes)
local function Top(t, n, minBytes, seen)
  local rows = {}
  for k, v in pairs(t) do
    local s = Size(v, seen)
    if s >= minBytes then rows[#rows + 1] = { k = tostring(k), s = s } end
  end
  table.sort(rows, function(a, b) return a.s > b.s end)
  local out = {}
  for i = 1, math.min(n, #rows) do out[i] = rows[i].k .. " " .. KB(rows[i].s) end
  return table.concat(out, ", ")
end

-- /aishmem bench : allocation par appel des mises a jour periodiques (idempotentes : les rappeler ne change
-- rien a l'affichage). Meilleure de 3 series de 50 appels, pour ecarter un pas du ramasse-miettes en cours.
local function Bench(fn)
  local best
  for _ = 1, 3 do
    local m0 = collectgarbage("count")
    for _ = 1, 50 do pcall(fn) end
    local d = collectgarbage("count") - m0
    if d >= 0 and (not best or d < best) then best = d end
  end
  return (best or 0) * 1024 / 50
end

local function RunBench()
  local M = ns.Modules or {}
  local A = ns.Auras or {}
  local list = {}
  local function add(label, hz, fn) if type(fn) == "function" then list[#list + 1] = { label, hz, fn } end end
  -- hz : frequence d'appel approximative hors combat. Ticker de visibilite d'AishCore.lua (5 Hz) pour ces
  -- modules ; les autres ne sont appeles que sur evenement (0 = pas de debit estime).
  local TICKED = { ResourceCircle = true, HealthCircle = true, OutOfCombatResourceCircle = true,
                   UnitBars = true, PriorityBar = true }
  for name, mod in pairs(M) do
    if type(mod) == "table" then
      for _, f in ipairs({ "Update", "UpdateVisibility", "UpdateAllVisibility" }) do
        if type(mod[f]) == "function" then add(name .. "." .. f, TICKED[name] and 5 or 0, mod[f]) end
      end
    end
  end
  if A.MissingBuffs then add("MissingBuffs.CheckForMissings", 1, A.MissingBuffs.CheckForMissings) end
  -- Barre de rotation : polling toutes les 0,15 s (~7 Hz) tant qu'elle est affichee
  local PBb = M.PriorityBar and M.PriorityBar._memBench
  if PBb then
    local hz = PBb.displayed() and 7 or 0
    for _, f in ipairs({ "PollSlots", "ScanCooldownViewer", "ScanSpellUsable", "ScanLiveSwipeState" }) do
      add("PriorityBar." .. f, hz, PBb[f])
    end
  end
  add("Auras.ScanAuras", 1, A.ScanAuras)
  collectgarbage("collect")
  local rows = {}
  for _, e in ipairs(list) do
    local b = Bench(e[3])
    rows[#rows + 1] = { label = e[1], bytes = b, hz = e[2], rate = b * e[2] / 1024 }
  end
  table.sort(rows, function(a, b) return a.bytes > b.bytes end)
  for i = 1, math.min(15, #rows) do
    local r = rows[i]
    if r.hz > 0 then
      print(P .. string.format("%-44s %7.0f o/appel  (~%.1f Ko/s a %d Hz)", r.label, r.bytes, r.rate, r.hz))
    else
      print(P .. string.format("%-44s %7.0f o/appel  (sur evenement)", r.label, r.bytes))
    end
  end
  -- Detail par etape de la verification des Buffs manquants (l'etape qui affiche l'alerte inclut son affichage)
  local MB = A.MissingBuffs
  if MB and MB.ProbeRun then
    local runs = 50
    local acc = MB.ProbeRun(runs)
    local steps = {}
    for tag, kb in pairs(acc) do
      if kb > 0 then steps[#steps + 1] = string.format("%s=%.0f", tag, kb * 1024 / runs) end
    end
    table.sort(steps)
    print(P .. "Buffs manquants, o/appel par etape : " .. table.concat(steps, "  "))
  end
end

-- /aishmem prof : pendant 10 s, chaque fonction publique des modules (ns.Modules.*, ns.Auras, ns.Auras.*) est
-- enveloppee pour mesurer ce qu'elle alloue, puis tout est remis en place. Les fonctions locales appelees directement
-- (tickers internes) ne sont pas vues ; une fonction appelee par une autre compte aussi dans celle qui l'appelle.
local function RunProfile()
  local acc, cnt, restore = {}, {}, {}
  local function finish(label, m0, ...)
    local d = collectgarbage("count") - m0
    if d > 0 then acc[label] = acc[label] + d end
    cnt[label] = cnt[label] + 1
    return ...
  end
  local function Wrap(tbl, prefix, seen)
    if type(tbl) ~= "table" or seen[tbl] then return end
    seen[tbl] = true
    for k, f in pairs(tbl) do
      if type(f) == "function" and type(k) == "string" then
        local label = prefix .. "." .. k
        acc[label], cnt[label] = 0, 0
        restore[#restore + 1] = { tbl, k, f }
        tbl[k] = function(...)
          local m0 = collectgarbage("count")
          return finish(label, m0, f(...))
        end
      end
    end
  end
  local seen = {}
  for name, mod in pairs(ns.Modules or {}) do Wrap(mod, name, seen) end
  local A = ns.Auras
  if type(A) == "table" then
    Wrap(A, "Auras", seen)
    for name, sub in pairs(A) do
      if type(sub) == "table" and type(name) == "string" and name:sub(1, 1):match("%u") then Wrap(sub, "Auras." .. name, seen) end
    end
  end
  print(P .. string.format("profil : %d fonctions suivies pendant 10 s...", #restore))
  local m0, t0 = AddonMem(), GetTime()
  C_Timer.After(10, function()
    for _, r in ipairs(restore) do
      if r[1][r[2]] ~= r[3] then r[1][r[2]] = r[3] end
    end
    local dt = GetTime() - t0
    local rows = {}
    for label, kb in pairs(acc) do
      if kb > 0 then rows[#rows + 1] = { label = label, kb = kb, n = cnt[label] } end
    end
    table.sort(rows, function(a, b) return a.kb > b.kb end)
    print(P .. string.format("debit total pendant le profil : %.1f Ko/s", (AddonMem() - m0) / dt))
    for i = 1, math.min(15, #rows) do
      local r = rows[i]
      print(P .. string.format("%-48s %7.1f Ko/s  (%d appels)", r.label, r.kb / dt, r.n))
    end
    if #rows == 0 then print(P .. "aucune allocation dans les fonctions suivies : la source est une fonction locale (ticker)") end
  end)
end

SLASH_AISHMEM1 = "/aishmem"
SlashCmdList["AISHMEM"] = function(msg)
  if InCombatLockdown() then print(P .. "hors combat seulement") return end
  if msg and msg:lower():find("bench") then RunBench() return end
  if msg and msg:lower():find("prof") then RunProfile() return end
  if msg and msg:lower():find("trace") then
    if ns._memTrace then ns._memTrace.Run() else print(P .. "trace : Forever seulement") end
    return
  end
  local shown = AddonMem()
  collectgarbage("collect")
  local live = AddonMem()
  print(P .. string.format("affichee %.0f Ko | vivante %.0f Ko | garbage %.0f Ko", shown, live, shown - live))

  local seen = {}
  local db, aura = _G.AishaddonDB, _G.AishUIAuraDB
  local dbS = db and Size(db, seen) or 0
  local auraS = aura and Size(aura, seen) or 0
  print(P .. "AishaddonDB ~" .. KB(dbS) .. " | AishUIAuraDB ~" .. KB(auraS))
  local prof = ns.DB
  if type(prof) == "table" then print(P .. "  profil actif : " .. Top(prof, 8, 20 * 1024, {})) end
  if aura and type(aura.profiles) == "table" then
    for name, p in pairs(aura.profiles) do
      if type(p) == "table" then print(P .. "  auras[" .. tostring(name) .. "] : " .. Top(p, 5, 20 * 1024, {})) end
    end
  end

  local data = {
    { "SEARCH_INDEX", ns.SEARCH_INDEX }, { "ClassSpellLevels", ns.ClassSpellLevels },
    { "LevelGains", ns.LevelGains }, { "PatchNotes", ns.PatchNotes }, { "SpellGradients", ns.SpellGradients },
    { "Locales", ns.L },
  }
  local parts, dataS = {}, 0
  for _, d in ipairs(data) do
    if type(d[2]) == "table" then
      local s = Size(d[2], seen)
      dataS = dataS + s
      parts[#parts + 1] = d[1] .. " " .. KB(s)
    end
  end
  print(P .. "donnees ~" .. KB(dataS) .. " : " .. table.concat(parts, ", "))
  print(P .. string.format("reste (code, frames, etat des modules) ~%.0f Ko", live - (dbS + auraS + dataS) / 1024))

  print(P .. "mesure du debit de garbage sur 10 s...")
  local m0, t0 = AddonMem(), GetTime()
  local fh = ns._fontHookStats
  local fc0, fs0 = fh and fh.calls or 0, fh and fh.stacks or 0
  C_Timer.After(10, function()
    local m1 = AddonMem()
    local dt = GetTime() - t0
    print(P .. string.format("debit : %.1f Ko/s (%s)", (m1 - m0) / dt,
      InCombatLockdown() and "combat pendant la mesure" or "hors combat"))
    -- Crochet global de SetFont (Core.lua) : appels venant de tous les addons, et piles d'appels lues
    if fh then
      print(P .. string.format("crochet SetFont : %.0f appels/s (tous addons), %d piles lues", (fh.calls - fc0) / dt,
        fh.stacks - fs0))
    end
  end)
end

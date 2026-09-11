-- Debug.lua : profiler léger pour identifier les sources de ticks (/aishdebug)
local _, ns = ...

local _active       = false
local _afterCounts  = {}   -- [sourceKey] = count
local _tickerCounts = {}   -- [sourceKey] = count
local _origAfter    = C_Timer.After
local _origTicker   = C_Timer.NewTicker
local _reportTicker = nil  -- le ticker de rapport automatique

-- Extrait une clé lisible depuis debugstack (toutes sources, pas juste AishCore)
local function CleanStack(raw)
    local out = {}
    for line in raw:gmatch("[^\n]+") do
        -- Ignorer notre propre fichier Debug.lua
        if line:find("Debug%.lua") then
            -- skip
        elseif line:find("AddOns\\") then
            -- "Interface\AddOns\NomAddon\SousDossier\Fichier.lua:123"
            -- → "NomAddon/Fichier:123"
            local addon, file, lineno = line:match("AddOns\\([^\\]+)\\[^\\]*\\([^\\]+)%.lua:(%d+)")
            if addon and file then
                table.insert(out, addon .. "/" .. file .. ":" .. lineno)
            else
                local addon2, file2, lineno2 = line:match("AddOns\\([^\\]+)\\([^\\]+)%.lua:(%d+)")
                if addon2 then
                    table.insert(out, addon2 .. "/" .. file2 .. ":" .. lineno2)
                else
                    local addon3, lineno3 = line:match("AddOns\\([^\\]+)%.lua:(%d+)")
                    if addon3 then
                        table.insert(out, addon3 .. ":" .. lineno3)
                    end
                end
            end
        elseif line:find("%[C%]") then
            -- skip (appels C internes)
        elseif line:match("^%s*%(") then
            -- skip (lignes résumé "(X calls)")
        elseif line:find("FrameXML") or line:find("Blizzard_") then
            local file, lineno = line:match("([^\\]+)%.lua:(%d+)")
            if file then table.insert(out, "Blizzard/" .. file .. ":" .. lineno) end
        end
    end
    -- Fallback : première ligne non-vide/non-C de la stack brute
    if #out == 0 then
        for line in raw:gmatch("[^\n]+") do
            if line:find("Debug%.lua") then
                -- skip notre propre fichier
            elseif not line:match("^%s*%[C%]") and not line:match("^%s*%(") and line:match("%S") then
                local trimmed = line:match("^%s*(.-)%s*$")
                if #trimmed > 0 then
                    return "??" .. trimmed:sub(1, 80)
                end
            end
        end
        return "(inconnu)"
    end
    return table.concat(out, " ← ", 1, math.min(#out, 2))
end

local function HookTimers()
    C_Timer.After = function(delay, fn)
        local raw = debugstack(2, 6, 0)
        local key = CleanStack(raw)
        if key == "" then key = "(inconnu)" end
        _afterCounts[key] = (_afterCounts[key] or 0) + 1
        return _origAfter(delay, fn)
    end

    C_Timer.NewTicker = function(interval, fn, iterations)
        local raw = debugstack(2, 6, 0)
        local key = CleanStack(raw)
        if key == "" then key = "(inconnu)" end
        _tickerCounts[key] = (_tickerCounts[key] or 0) + 1
        return _origTicker(interval, fn, iterations)
    end
end

local function UnhookTimers()
    C_Timer.After     = _origAfter
    C_Timer.NewTicker = _origTicker
end

-- Rapport
local function SortedPairs(t)
    local keys = {}
    for k in pairs(t) do keys[#keys+1] = k end
    table.sort(keys, function(a, b) return t[a] > t[b] end)
    return keys
end

local function PrintReport()
    local total = 0
    for _, v in pairs(_afterCounts) do total = total + v end

    print("|cff00ccffAishCore Debug|r — C_Timer.After depuis le dernier reset (total : " .. total .. ")")

    local keys = SortedPairs(_afterCounts)
    if #keys == 0 then
        print("  (aucun appel enregistré)")
    else
        for i = 1, math.min(#keys, 15) do
            local k = keys[i]
            local pct = math.floor(_afterCounts[k] / math.max(total, 1) * 100)
            print(string.format("  |cffff9900%4d|r (%2d%%)  %s", _afterCounts[k], pct, k))
        end
    end

    -- NewTicker
    local totalT = 0
    for _, v in pairs(_tickerCounts) do totalT = totalT + v end
    if totalT > 0 then
        print("|cff00ccffAishCore Debug|r — C_Timer.NewTicker créés (total : " .. totalT .. ")")
        local tkeys = SortedPairs(_tickerCounts)
        for i = 1, math.min(#tkeys, 10) do
            local k = tkeys[i]
            print(string.format("  |cffff9900%4d|r  %s", _tickerCounts[k], k))
        end
    end
end

-- Slash command
SLASH_AISHDEBUG1 = "/aishdebug"
SlashCmdList["AISHDEBUG"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")

    if msg == "on" then
        if _active then
            print("|cff00ccffAishCore Debug|r Déjà actif.")
            return
        end
        _active = true
        wipe(_afterCounts)
        wipe(_tickerCounts)
        HookTimers()
        -- Rapport automatique toutes les 5 secondes
        _reportTicker = _origTicker(5, function()
            if _active then PrintReport() end
        end)
        print("|cff00ccffAishCore Debug|r |cff00ff00DÉMARRÉ|r — rapport toutes les 5s. /aishdebug off pour arrêter.")

    elseif msg == "off" then
        if not _active then
            print("|cff00ccffAishCore Debug|r Pas actif.")
            return
        end
        _active = false
        if _reportTicker then _reportTicker:Cancel(); _reportTicker = nil end
        UnhookTimers()
        PrintReport()
        print("|cff00ccffAishCore Debug|r |cffff0000ARRÊTÉ|r.")

    elseif msg == "report" then
        PrintReport()

    elseif msg == "reset" then
        wipe(_afterCounts)
        wipe(_tickerCounts)
        print("|cff00ccffAishCore Debug|r Compteurs remis à zéro.")

    elseif msg == "sky" then
        local sky = ns.Modules and ns.Modules.Skyriding
        if sky and sky.DebugDump then
            sky.DebugDump()
        else
            print("|cff00ccffAishCore Debug|r |cffff4444Module Skyriding introuvable (pas encore chargé ?).|r")
        end

    elseif msg == "cdm" then
        DumpCooldownViewer()

    elseif msg == "cdmbuff" then
        DumpBuffCooldownViewer()

    elseif msg == "bars" then
        local auras = ns.Auras
        if auras and auras.DebugDurationBars then
            auras.DebugDurationBars()
        else
            print("|cff00ccffAishCore Debug|r |cffff4444DebugDurationBars introuvable (ns.Auras absent ou pas encore charge).|r")
        end

    elseif msg == "cdvoff" then
        ns._cdViewerDisabled = true
        print("|cff00ccffAishCore Debug|r CDViewer scan |cffff0000DÉSACTIVÉ|r. /aishdebug cdvon pour réactiver.")

    elseif msg == "cdvon" then
        ns._cdViewerDisabled = false
        print("|cff00ccffAishCore Debug|r CDViewer scan |cff00ff00ACTIVÉ|r.")

    elseif msg == "pbslots" then
        DumpPBSlots()

    elseif msg == "pbcharges" then
        DumpPBCharges()

    elseif msg == "buffs" then
        local vis = ns.Modules and ns.Modules.Visibility
        if vis and vis.Debug then
            vis.Debug()
        else
            print("|cff00ccffAishCore Debug|r |cffff4444Module Visibility introuvable (pas encore chargé ?).|r")
        end

    elseif msg:match("^pin%s+%d+") then
        local spellIDStr, mode = msg:match("^pin%s+(%d+)%s*(%a*)$")
        local spellID = tonumber(spellIDStr)
        local auras = ns.Auras
        if not (auras and auras.PinAuraToCDM) then
            print("|cff00ccffAishCore Debug|r |cffff4444ns.Auras.PinAuraToCDM introuvable (module pas chargé ?).|r")
        elseif not spellID then
            print("|cff00ccffAishCore Debug|r usage : /aishdebug pin <spellID> [icon]")
        else
            local asBar = (mode ~= "icon")
            local success, statusMsg = auras.PinAuraToCDM(spellID, asBar)
            local color = success and "|cff00ff00" or "|cffff4444"
            print(string.format("|cff00ccffAishCore Debug|r pin %d (%s) -> %s%s|r",
                spellID, asBar and "barre" or "icone", color, tostring(statusMsg)))
            if success and auras.PromptCDMReloadIfPending then auras.PromptCDMReloadIfPending() end
        end

    elseif msg == "syncpins" then
        local auras = ns.Auras
        if not (auras and auras.SyncCDMPins) then
            print("|cff00ccffAishCore Debug|r |cffff4444ns.Auras.SyncCDMPins introuvable (module pas chargé ?).|r")
        else
            local ok, a, b, c = auras.SyncCDMPins()
            if not ok then
                print("|cff00ccffAishCore Debug|r |cffff4444Sync refusée : " .. tostring(a) .. "|r")
            else
                local pinned, skipped, failures = a, b, c
                print(string.format("|cff00ccffAishCore Debug|r Sync CDM : |cff00ff00%d épinglé(s)|r, |cffffff00%d ignoré(s)|r",
                    pinned, skipped))
                if failures and #failures > 0 then
                    for _, line in ipairs(failures) do
                        print("  |cffff8800" .. line .. "|r")
                    end
                end
                if pinned > 0 and auras.PromptCDMReloadIfPending then auras.PromptCDMReloadIfPending() end
            end
        end

    elseif msg:match("^auratrace%s+%d+") then
        local spellIDStr = msg:match("^auratrace%s+(%d+)$")
        local spellID = tonumber(spellIDStr)
        local auras = ns.Auras
        if not (auras and auras.DebugTraceAura) then
            print("|cff00ccffAishCore Debug|r |cffff4444ns.Auras.DebugTraceAura introuvable (module pas chargé ?).|r")
        else
            auras.DebugTraceAura(spellID)
        end

    elseif msg == "cdmreload" then
        local auras = ns.Auras
        if not (auras and auras.GetCDMReloadPendingCount) then
            print("|cff00ccffAishCore Debug|r |cffff4444ns.Auras.GetCDMReloadPendingCount introuvable (module pas chargé ?).|r")
        else
            print(string.format("|cff00ccffAishCore Debug|r pendingCDMReloadCount = |cffffff00%d|r", auras.GetCDMReloadPendingCount()))
            local log = auras._cdmReloadMarkLog
            if log and #log > 0 then
                print("  Historique des increments (plus recent en premier) :")
                for _, e in ipairs(log) do
                    print(string.format("  +%d -> total=%d  il y a %.1fs  |cff888888%s|r",
                        e.count, e.total, GetTime() - e.t, tostring(e.src):gsub("\n", " | ")))
                end
            else
                print("  Aucun increment enregistre cette session.")
            end
        end

    elseif msg == "iconsflow" or msg:match("^iconsflow%s+%d+$") then
        local auras = ns.Auras
        if not (auras and auras.DebugDumpIconsFlow) then
            print("|cff00ccffAishCore Debug|r |cffff4444ns.Auras.DebugDumpIconsFlow introuvable (module pas chargé ?).|r")
        else
            -- Filtre optionnel par spellID : le dump complet depasse facilement
            -- la centaine de boutons (un pool natif par sort traque), illisible
            -- dans le chat -- "/aishdebug iconsflow 187878" ne sort que ce sort.
            auras.DebugDumpIconsFlow(tonumber(msg:match("(%d+)$")))
        end

    elseif msg == "circlebarsflow" then
        local auras = ns.Auras
        if not (auras and auras.DebugDumpCircleBarsFlow) then
            print("|cff00ccffAishCore Debug|r |cffff4444ns.Auras.DebugDumpCircleBarsFlow introuvable (module pas chargé ?).|r")
        else
            auras.DebugDumpCircleBarsFlow()
        end

    elseif msg == "totem" then
        local auras = ns.Auras
        if not (auras and auras.DebugDumpTotems) then
            print("|cff00ccffAishCore Debug|r |cffff4444ns.Auras.DebugDumpTotems introuvable (module pas chargé ?).|r")
        else
            auras.DebugDumpTotems()
        end

    elseif msg == "groups" then
        local auras = ns.Auras
        if not (auras and auras.DebugDumpGroupCounts) then
            print("|cff00ccffAishCore Debug|r |cffff4444ns.Auras.DebugDumpGroupCounts introuvable (module pas chargé ?).|r")
        else
            auras.DebugDumpGroupCounts()
        end
        -- Memoire Lua totale (UpdateAddOnMemoryUsage doit avoir tourné récemment)
        if UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
            UpdateAddOnMemoryUsage()
            local mem = GetAddOnMemoryUsage("AishCore")
            print(string.format("|cff00ccffAishCore Debug|r Memoire Lua totale addon (instantanee) : %.2f Mo", (mem or 0) / 1024))
        end

    elseif msg == "iconlistrows" then
        local auras = ns.Auras
        if not (auras and auras.DebugDumpIconListRows) then
            print("|cff00ccffAishCore Debug|r |cffff4444ns.Auras.DebugDumpIconListRows introuvable (module pas chargé ?).|r")
        else
            auras.DebugDumpIconListRows()
        end

    elseif msg:match("^spell%s+%d") then
        local argsStr = msg:match("^spell%s+(.+)$")
        local spellIDs = {}
        for numStr in argsStr:gmatch("%d+") do
            spellIDs[#spellIDs + 1] = tonumber(numStr)
        end
        local auras = ns.Auras
        if not (auras and auras.DebugDumpSpellTracking) then
            print("|cff00ccffAishCore Debug|r |cffff4444ns.Auras.DebugDumpSpellTracking introuvable (module pas chargé ?).|r")
        else
            auras.DebugDumpSpellTracking(unpack(spellIDs))
        end

    elseif msg == "circlebarswatch" then
        local auras = ns.Auras
        if not (auras and auras.DebugCircleBarsWatchToggle) then
            print("|cff00ccffAishCore Debug|r |cffff4444ns.Auras.DebugCircleBarsWatchToggle introuvable (module pas chargé ?).|r")
        else
            auras.DebugCircleBarsWatchToggle()
        end

    elseif msg:match("^testcontainer%s+%d") then
        local argsStr = msg:match("^testcontainer%s+(.+)$")
        local spellIDs = {}
        for numStr in argsStr:gmatch("%d+") do
            spellIDs[#spellIDs + 1] = tonumber(numStr)
        end
        local auras = ns.Auras
        if not (auras and auras.DebugTestNativeContainer) then
            print("|cff00ccffAishCore Debug|r |cffff4444ns.Auras.DebugTestNativeContainer introuvable (module pas chargé ?).|r")
        else
            auras.DebugTestNativeContainer(spellIDs)
        end

    elseif msg:match("^testbar%s+%d") then
        local argsStr = msg:match("^testbar%s+(.+)$")
        local spellIDs = {}
        for numStr in argsStr:gmatch("%d+") do
            spellIDs[#spellIDs + 1] = tonumber(numStr)
        end
        local auras = ns.Auras
        if not (auras and auras.DebugTestBarOnlyGroup) then
            print("|cff00ccffAishCore Debug|r |cffff4444ns.Auras.DebugTestBarOnlyGroup introuvable (module pas chargé ?).|r")
        else
            auras.DebugTestBarOnlyGroup(spellIDs)
        end

    elseif msg:match("^testmulti%s+%d") then
        local argsStr = msg:match("^testmulti%s+(.+)$")
        local spellIDs = {}
        for numStr in argsStr:gmatch("%d+") do
            spellIDs[#spellIDs + 1] = tonumber(numStr)
        end
        local auras = ns.Auras
        if not (auras and auras.DebugTestMultiGroup) then
            print("|cff00ccffAishCore Debug|r |cffff4444ns.Auras.DebugTestMultiGroup introuvable (module pas chargé ?).|r")
        else
            auras.DebugTestMultiGroup(spellIDs)
        end

    elseif msg:match("^testpercolor%s+%d") then
        local argsStr = msg:match("^testpercolor%s+(.+)$")
        local spellIDs = {}
        for numStr in argsStr:gmatch("%d+") do
            spellIDs[#spellIDs + 1] = tonumber(numStr)
        end
        local auras = ns.Auras
        if not (auras and auras.DebugTestPerSpellGroup) then
            print("|cff00ccffAishCore Debug|r |cffff4444ns.Auras.DebugTestPerSpellGroup introuvable (module pas chargé ?).|r")
        else
            auras.DebugTestPerSpellGroup(spellIDs)
        end

    else
        print("|cff00ccffAishCore Debug|r commandes :")
        print("  /aishdebug |cff00ff00on|r      — démarre le profiling (rapport auto /5s)")
        print("  /aishdebug |cffff0000off|r     — arrête + rapport final")
        print("  /aishdebug |cffffff00report|r  — rapport immédiat")
        print("  /aishdebug |cffffff00reset|r   — remet les compteurs à zéro")
        print("  /aishdebug |cffffff00sky|r     — état complet du HUD Skyriding + journal")
        print("  /aishdebug |cffffff00cdm|r     — dump Blizzard CooldownViewer (Utility)")
        print("  /aishdebug |cffffff00cdmbuff|r — dump BuffIcon/BuffBar CooldownViewer (duree buffs)")
        print("  /aishdebug |cffffff00bars|r    — etat interne des barres de duree (binding natif)")
        print("  /aishdebug |cffffff00cdvoff|r  — désactive le scan CDViewer (test icones)")
        print("  /aishdebug |cffffff00cdvon|r   — réactive le scan CDViewer")
        print("  /aishdebug |cffffff00pbslots|r — dump état des 4 slots PriorityBar")
        print("  /aishdebug |cffffff00pbcharges|r — trace résolution charges par slot")
        print("  /aishdebug |cffffff00buffs|r   — diagnostic fade zone de buffs ElvUI")
        print("  /aishdebug |cffffff00pin <spellID> [icon]|r — [EXPÉRIMENTAL v3] épingle un sort dans le CDM natif, reload forcé ensuite (hors combat uniquement)")
        print("  /aishdebug |cffffff00syncpins|r — [EXPÉRIMENTAL v3] épingle en masse la whitelist de la spec active, reload forcé ensuite (hors combat uniquement)")
        print("  /aishdebug |cffffff00auratrace <spellID>|r — trace pas-a-pas la detection de presence pour ce sort (player+target)")
        print("  /aishdebug |cffffff00cdmreload|r — affiche le compteur de reload CDM en attente + historique des increments")
        print("  /aishdebug |cffffff00iconlistrows|r — dump direct des boutons Liste d'icones reellement crees (joueur+cible), spellID assigne, visible ou non")
        print("  /aishdebug |cffffff00testcontainer <spellID> [spellID2...]|r — [TEST] cree un AuraContainer natif isole (icone+stacks+cooldown) pour valider l'approche, hors combat uniquement")
        print("  /aishdebug |cffffff00testbar <spellID> [spellID2...]|r — [TEST] AddAuraGroup sans icone/sans flow layout, juste une StatusBar via SetDurationBar (prepare la migration Circle Bars)")
        print("  /aishdebug |cffffff00testmulti <spellID1> <spellID2>|r — [TEST] AddAuraGroup maxFrameCount=3, 2+ sorts DIFFERENTS -- verifie si 2 candidats simultanes peuvent s'afficher en meme temps (isole de Circle Bars)")
        print("  /aishdebug |cffffff00testpercolor <spellID1> <spellID2>|r — [TEST] UN AddAuraGroup DEDIE par sort (maxFrameCount=1) -- verifie si la couleur/glow PAR SORT est possible avec le systeme natif")
        print("  /aishdebug |cffffff00iconsflow [spellID]|r — [DEBUG] dump de l'etat du rendu natif 'icons' (conteneur/groupe/boutons/layout) ; spellID = ne garder que ce sort")
        print("  /aishdebug |cffffff00circlebarsflow|r — [DEBUG] dump complet de l'etat du rendu natif 'Circle Bars' (Buffs.lua/freebars)")
        print("  /aishdebug |cffffff00circlebarswatch|r — [DEBUG] force UpdateAllAuras toutes les 0.5s + log les changements (bascule on/off)")
        print("  /aishdebug |cffffff00groups|r — [CHECKUP MEMOIRE] compte les AddAuraGroup dedies crees (jamais liberables) sur les 4 destinations + memoire Lua totale de l'addon")
        print("  /aishdebug |cffffff00totem|r — [DEBUG] dump complet de l'etat totems (sorts traques, scan GetTotemInfo brut, conteneur/widgets)")
    end
end

-- /aishdebug pbslots — Dump l'état actuel des 4 slots PriorityBar
function DumpPBSlots()
    local P = function(s) print("|cffFF8800[PB]|r " .. s) end
    local PB = ns.Modules and ns.Modules.PriorityBar
    if not PB then P("|cffff4444PriorityBar introuvable|r"); return end

    -- Accéder aux données internes via le module exposé
    local slots = PB._debug_slotFrames
    if not slots then P("|cffff4444_debug_slotFrames non exposé|r"); return end

    for i = 1, 4 do
        local slot = slots[i]
        if slot then
            local cfgIDs = slot.spellIDs or {}
            local cfgNames = {}
            for _, sid in ipairs(cfgIDs) do
                local name = "?"
                if C_Spell and C_Spell.GetSpellName then
                    local ok, n = pcall(C_Spell.GetSpellName, sid)
                    if ok and n then name = n end
                end
                table.insert(cfgNames, name .. "(" .. sid .. ")")
            end

            local displayID = slot.currentSpellID
            local displayName = "nil"
            if displayID then
                local ok, n = pcall(C_Spell.GetSpellName, displayID)
                if ok and n then displayName = n end
            end

            local isHL = slot._isHighlighted and "OUI" or "non"
            local desat = (slot.icon and slot.icon:IsDesaturated()) and "DESAT" or "normal"
            local tex = slot._displayTex and (tostring(slot._displayTex):sub(1, 40)) or "nil"
            local chargeTxt = "hidden"
            if slot.chargeText and slot.chargeText:IsShown() then
                chargeTxt = slot.chargeText:GetText() or "?"
            end

            P(string.format("|cff88ccffSlot %d|r  config=[%s]", i, table.concat(cfgNames, ", ")))
            P(string.format("  display=%s(%s)  HL=%s  %s  charges=%s  tex=%s",
                displayName, tostring(displayID), isHL, desat, chargeTxt, tex))
        else
            P(string.format("|cff88ccffSlot %d|r  <nil>", i))
        end
    end
end

-- /aishdebug pbcharges — Trace la résolution des charges pour chaque slot (CDViewer vs fallback)
function DumpPBCharges()
    local P = function(s) print("|cffFF8800[CHG]|r " .. s) end
    local PB = ns.Modules and ns.Modules.PriorityBar
    if not PB then P("|cffff4444PriorityBar introuvable|r"); return end

    local slots = PB._debug_slotFrames
    local dbg   = PB._debug_internals
    if not slots or not dbg then
        P("|cffff4444_debug_slotFrames ou _debug_internals non exposé|r")
        return
    end

    local chargeCache      = dbg.chargeCache or {}
    local overrideToBase   = dbg.overrideToBase or {}
    local estimatedCharges = dbg.estimatedCharges or {}
    local _cdViewerState   = dbg._cdViewerState or {}
    local _cdViewerAvail   = PB._debug_getCdViewerAvail and PB._debug_getCdViewerAvail() or false

    P("--- CDViewer avail=" .. tostring(_cdViewerAvail) .. " ---")

    -- Dump tout le _cdViewerState pour voir les clés
    local cvKeys = {}
    for sid, cv in pairs(_cdViewerState) do
        local name = "?"
        local ok, n = pcall(C_Spell.GetSpellName, sid)
        if ok and n then name = n end
        table.insert(cvKeys, string.format("  %s(%d) onCD=%s charges=%s",
            name, sid, tostring(cv.onCD), tostring(cv.charges)))
    end
    P("CDViewer state (" .. #cvKeys .. " entrées):")
    for _, line in ipairs(cvKeys) do P(line) end

    -- Dump chargeCache
    local ccKeys = {}
    for sid, maxC in pairs(chargeCache) do
        local name = "?"
        local ok, n = pcall(C_Spell.GetSpellName, sid)
        if ok and n then name = n end
        table.insert(ccKeys, string.format("  %s(%d) max=%d est=%s",
            name, sid, maxC, tostring(estimatedCharges[sid])))
    end
    P("chargeCache (" .. #ccKeys .. " entrées):")
    for _, line in ipairs(ccKeys) do P(line) end

    -- Diagnostic GetSpellCharges en combat
    -- NOTE : En TWW, les secret numbers bloquent TOUTE opération Lua.
    -- On affiche juste tostring (qui marche) pour référence.
    P("--- GetSpellCharges LIVE (combat test) ---")
    for sid, maxC in pairs(chargeCache) do
        local name = "?"
        local ok, n = pcall(C_Spell.GetSpellName, sid)
        if ok and n then name = n end
        if C_Spell and C_Spell.GetSpellCharges then
            local okG, info = pcall(C_Spell.GetSpellCharges, sid)
            if okG and info and info.currentCharges ~= nil then
                P(string.format("  %s(%d): realCharges=%s (secret/tainted) est=%s max=%d",
                    name, sid,
                    tostring(info.currentCharges),
                    tostring(estimatedCharges[sid]),
                    maxC))
            elseif okG then
                P(string.format("  %s(%d): GetSpellCharges nil", name, sid))
            else
                P(string.format("  %s(%d): FAILED: %s", name, sid, tostring(info)))
            end
        end
    end

    P("--- Par slot ---")
    for i = 1, 4 do
        local slot = slots[i]
        if not slot or not slot.currentSpellID then
            P(string.format("Slot %d: pas de sort", i))
        else
            local displayedID   = slot.currentSpellID
            local baseDisplayed = overrideToBase[displayedID] or displayedID
            local displayName = "?"
            local ok, n = pcall(C_Spell.GetSpellName, displayedID)
            if ok and n then displayName = n end

            P(string.format("|cff88ccffSlot %d|r display=%s(%d) base=%d",
                i, displayName, displayedID, baseDisplayed))

            -- chargeCache match
            local ccDirect = chargeCache[displayedID]
            local ccBase   = chargeCache[baseDisplayed]
            P(string.format("  chargeCache[display]=%s  chargeCache[base]=%s",
                tostring(ccDirect), tostring(ccBase)))

            -- Override live match
            if slot.spellIDs and C_Spell and C_Spell.GetOverrideSpell then
                for _, sid in ipairs(slot.spellIDs) do
                    if chargeCache[sid] then
                        local okOv, ov = pcall(C_Spell.GetOverrideSpell, sid)
                        P(string.format("  config %d: chargeCache=%d override=%s match=%s",
                            sid, chargeCache[sid],
                            okOv and tostring(ov) or "err",
                            okOv and ov == displayedID and "OUI" or "non"))
                    end
                end
            end

            -- CDViewer lookup
            local cv1 = _cdViewerState[displayedID]
            local cv2 = _cdViewerState[baseDisplayed]
            P(string.format("  cvState[display]=%s  cvState[base]=%s",
                cv1 and string.format("onCD=%s ch=%s", tostring(cv1.onCD), tostring(cv1.charges)) or "nil",
                cv2 and string.format("onCD=%s ch=%s", tostring(cv2.onCD), tostring(cv2.charges)) or "nil"))

            -- Check slot.spellIDs dans CDViewer
            if slot.spellIDs then
                for _, sid in ipairs(slot.spellIDs) do
                    local cvs = _cdViewerState[sid]
                    if cvs then
                        local sname = "?"
                        local ok2, n2 = pcall(C_Spell.GetSpellName, sid)
                        if ok2 and n2 then sname = n2 end
                        P(string.format("  cvState[config %s(%d)]= onCD=%s ch=%s",
                            sname, sid, tostring(cvs.onCD), tostring(cvs.charges)))
                    end
                end
            end

            -- Ce que le PB affiche actuellement
            local chargeTxt = "hidden"
            if slot.chargeText and slot.chargeText:IsShown() then
                chargeTxt = slot.chargeText:GetText() or "?"
            end
            P(string.format("  |cffffffaaAFFICHÉ: charges=%s|r", chargeTxt))
        end
    end
end

-- /aishdebug cdm — Dump du UtilityCooldownViewer Blizzard (champs publics CD/charges)
function DumpCooldownViewer()
    local P = function(s) print("|cffFF8800[CDM]|r " .. s) end

    local viewer = _G["UtilityCooldownViewer"]
    if not viewer or not viewer.itemFramePool then
        P("|cffff4444UtilityCooldownViewer introuvable|r")
        return
    end

    -- === MÉTHODES DE DÉTECTION ===

    -- M1: Countdown text (FontString dans le Cooldown widget)
    local function M1_CooldownText(itemFrame)
        local ok, text = pcall(function()
            if itemFrame.Cooldown then
                local regions = { itemFrame.Cooldown:GetRegions() }
                for _, region in ipairs(regions) do
                    if region.GetText then
                        local t = region:GetText()
                        if t then local _ = t .. ""; return t end
                    end
                end
            end
            return nil
        end)
        if ok then return text end
        return nil
    end

    -- M2: Cooldown:IsShown() / IsVisible()
    local function M2_CooldownShown(itemFrame)
        local ok, val = pcall(function()
            if itemFrame.Cooldown then
                return itemFrame.Cooldown:IsShown() and "shown" or "hidden"
            end
            return "noCDframe"
        end)
        if ok then return val end
        return "secret"
    end

    -- M3: GetCooldownTimes() du widget Cooldown natif
    local function M3_CooldownTimes(itemFrame)
        local ok, result = pcall(function()
            if itemFrame.Cooldown and itemFrame.Cooldown.GetCooldownTimes then
                local start, dur = itemFrame.Cooldown:GetCooldownTimes()
                if start and dur then
                    -- Tenter une comparaison pour voir si tainted
                    if start > 0 then return string.format("s=%.0f d=%.0f", start, dur) end
                    return "0/0"
                end
            end
            return "noAPI"
        end)
        if ok then return result end
        return "secret"
    end

    -- M4: GetCooldownDisplayDuration()
    local function M4_DisplayDuration(itemFrame)
        local ok, result = pcall(function()
            if itemFrame.Cooldown and itemFrame.Cooldown.GetCooldownDisplayDuration then
                local d = itemFrame.Cooldown:GetCooldownDisplayDuration()
                if d and d > 0 then return string.format("%.1f", d) end
                return "0"
            end
            return "noAPI"
        end)
        if ok then return result end
        return "secret"
    end

    -- M5: Icon:GetDesaturation() (valeur 0-1, pas booléen)
    local function M5_Desaturation(itemFrame)
        local ok, val = pcall(function()
            if itemFrame.Icon and itemFrame.Icon.GetDesaturation then
                local d = itemFrame.Icon:GetDesaturation()
                if d and d > 0 then return string.format("%.2f", d) end
                return "0"
            end
            return "noAPI"
        end)
        if ok then return val end
        return "secret"
    end

    -- M6: Cooldown swipe alpha
    local function M6_CooldownAlpha(itemFrame)
        local ok, val = pcall(function()
            if itemFrame.Cooldown then
                local a = itemFrame.Cooldown:GetAlpha()
                return string.format("%.2f", a)
            end
            return "noCD"
        end)
        if ok then return val end
        return "secret"
    end

    -- M7: Charge text lisible
    local function M7_ChargeText(itemFrame)
        local ok, text = pcall(function()
            if itemFrame.ChargeCount and itemFrame.ChargeCount.Current then
                local t = itemFrame.ChargeCount.Current:GetText()
                if t then local _ = t .. ""; return t end
            end
            return nil
        end)
        if ok then return text end
        return "<secret>"
    end

    P("--- V6 : Multi-détection (Pénitence+AttMentale = EN CD) ---")

    local ok_enum, err_enum = pcall(function()
        for itemFrame in viewer.itemFramePool:EnumerateActive() do
            local info = itemFrame.cooldownInfo
            local spellID = info and info.spellID
            local spellName = "?"
            if spellID then
                local ok, v = pcall(C_Spell.GetSpellName, spellID)
                if ok and v then spellName = v end
            end

            local m1 = M1_CooldownText(itemFrame)
            local m2 = M2_CooldownShown(itemFrame)
            local m3 = M3_CooldownTimes(itemFrame)
            local m4 = M4_DisplayDuration(itemFrame)
            local m5 = M5_Desaturation(itemFrame)
            local m6 = M6_CooldownAlpha(itemFrame)
            local m7 = M7_ChargeText(itemFrame)

            P(string.format("%s (%s)", spellName, tostring(spellID)))
            P(string.format("  txt=%s  shown=%s  times=%s  disp=%s  desat=%s  alpha=%s  chrg=%s",
                tostring(m1), m2, m3, m4, m5, m6, tostring(m7)))
        end
    end)

    if not ok_enum then
        P("|cffff4444ERREUR : " .. tostring(err_enum) .. "|r")
    end

    P("--- Fin V6 ---")
end

-- /aishdebug cdmbuff — Meme sondage que DumpCooldownViewer mais sur BuffIcon/BuffBarCooldownViewer
-- (buffs traqués, pas debuffs cible). Vérifie si Cooldown:GetCooldownTimes()/
-- GetCooldownDisplayDuration() sont lisibles (non secrètes) sur un buff en combat.
function DumpBuffCooldownViewer()
    local P = function(s) print("|cffFF8800[CDMBUFF]|r " .. s) end

    local function M1_CooldownText(itemFrame)
        local ok, text = pcall(function()
            if itemFrame.Cooldown then
                for _, region in ipairs({ itemFrame.Cooldown:GetRegions() }) do
                    if region.GetText then
                        local t = region:GetText()
                        if t then local _ = t .. ""; return t end
                    end
                end
            end
            return nil
        end)
        if ok then return text end
        return "<secret>"
    end

    local function M3_CooldownTimes(itemFrame)
        local ok, result = pcall(function()
            if itemFrame.Cooldown and itemFrame.Cooldown.GetCooldownTimes then
                local start, dur = itemFrame.Cooldown:GetCooldownTimes()
                if start and dur then
                    if start > 0 then return string.format("s=%.0f d=%.0f", start, dur) end
                    return "0/0"
                end
            end
            return "noAPI"
        end)
        if ok then return result end
        return "secret"
    end

    local function M4_DisplayDuration(itemFrame)
        local ok, result = pcall(function()
            if itemFrame.Cooldown and itemFrame.Cooldown.GetCooldownDisplayDuration then
                local d = itemFrame.Cooldown:GetCooldownDisplayDuration()
                if d and d > 0 then return string.format("%.1f", d) end
                return "0"
            end
            return "noAPI"
        end)
        if ok then return result end
        return "secret"
    end

    local function M6_CooldownAlpha(itemFrame)
        local ok, val = pcall(function()
            if itemFrame.Cooldown then
                return string.format("%.2f", itemFrame.Cooldown:GetAlpha())
            end
            return "noCD"
        end)
        if ok then return val end
        return "secret"
    end

    for _, viewerName in ipairs({ "BuffIconCooldownViewer", "BuffBarCooldownViewer" }) do
        local viewer = _G[viewerName]
        if not viewer or not viewer.itemFramePool then
            P(viewerName .. " introuvable")
        else
            P("--- " .. viewerName .. " ---")
            local ok_enum, err_enum = pcall(function()
                for itemFrame in viewer.itemFramePool:EnumerateActive() do
                    local info = itemFrame.cooldownInfo
                    local spellID = info and info.spellID
                    local spellName = "?"
                    if spellID then
                        local okN, v = pcall(C_Spell.GetSpellName, spellID)
                        if okN and v then spellName = v end
                    end
                    P(string.format("%s (%s)  txt=%s  times=%s  disp=%s  alpha=%s",
                        spellName, tostring(spellID),
                        tostring(M1_CooldownText(itemFrame)),
                        M3_CooldownTimes(itemFrame),
                        M4_DisplayDuration(itemFrame),
                        M6_CooldownAlpha(itemFrame)))
                end
            end)
            if not ok_enum then P("|cffff4444ERREUR : " .. tostring(err_enum) .. "|r") end
        end
    end
end



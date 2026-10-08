--[[
    Laufzeit-Tests mit nachgebauter WoW-API.

    Aufruf (aus dem Hauptordner des Addons):
        lua5.1 tests/run.lua forever
        lua5.1 tests/run.lua retail
    oder alles zusammen: sh tests/run.sh

    Jedes Profil laeuft in einem eigenen Prozess, weil das Addon mit
    globalen Tabellen arbeitet. Ist GK_CODES_OUT gesetzt, schreibt der Lauf
    die erzeugten Webseiten-Codes in diese Datei (fuer tests/check_gkw.py,
    den Gegentest mit dem Parser der Webseite).
]]

package.path = "./tests/?.lua;" .. package.path
local Stub = require("wowstub")
local profile = arg[1] or "forever"
local forever = profile == "forever"

-- Forever auf Deutsch, Retail auf Englisch: so laufen beide Sprachen durch
Stub.locale = forever and "deDE" or "enUS"
Stub.Install(profile)
Stub.LoadAddon(".")
Stub.Fire("ADDON_LOADED", "Grindkeep")
Stub.Fire("PLAYER_LOGIN")
Stub.RunTimers()

local DB = GrindkeepDatabase
local Comm = GrindkeepComm
local Web = GrindkeepWebExport

-- ------------------------------------------------------------
-- Mini-Testrahmen
-- ------------------------------------------------------------
local passed, failed = 0, 0
local out = io.stdout

local function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
    else
        failed = failed + 1
        out:write(("FAIL [%s] %s\n    %s\n"):format(profile, name, tostring(err)))
    end
end

local function eq(actual, expected, what)
    if actual ~= expected then
        error(("%s: erwartet %s, bekommen %s"):format(what or "Wert", tostring(expected), tostring(actual)), 2)
    end
end

local function truthy(v, what) if not v then error((what or "Bedingung") .. " nicht erfuellt", 2) end end

local function split(s, sep)
    local t = {}
    for f in (s .. sep):gmatch("(.-)" .. sep) do t[#t + 1] = f end
    return t
end

-- Nutzlast in Zeilen und Felder zerlegen
local function rowsOf(payload)
    local rows = {}
    for _, line in ipairs(split(payload, "\n")) do
        if line ~= "" then rows[#rows + 1] = split(line, "\t") end
    end
    return rows
end

-- Webseiten-Code wie die Webseite pruefen und dekodieren
local function decodeCode(code)
    local prefix, b64, chk = code:match("^(GKW1):([%w%+/=]+):(%x+)$")
    truthy(prefix, "Huelle GKW1:<Base64>:<Adler-32>")
    local payload = Comm._Base64Decode(b64)
    eq(Web.Adler32(payload), chk, "Pruefsumme")
    return payload
end

-- ------------------------------------------------------------
-- Testdaten: Gildenbank mit Log und Inhalt
-- ------------------------------------------------------------
Stub.bank.logs[1] = {
    { type = "deposit", name = "Krutolo Zitterhand", id = 2770, count = 20, hours = 2 },
    { type = "withdraw", name = "Anna Meier-Schulz", id = 2770, count = 5, hours = 1 },
}
Stub.bank.logs[2] = {
    { type = "deposit", name = Stub.playerName, id = 2589, count = 40, hours = 3 },
}
Stub.bank.money = {
    { type = "deposit", name = Stub.playerName, amount = 125000, hours = 1 },
}
Stub.bank.slots[1] = { { id = 2770, count = 20 }, { id = 2770, count = 15 }, { id = 19019, count = 1 } }
Stub.bank.slots[2] = { { id = 2589, count = 40 }, { id = 13444, count = 12 } }

local function RunBankVisit()
    Stub.queries = {}
    Stub.Fire("GUILDBANKFRAME_OPENED")
    Stub.RunTimers() -- verzoegerter Scan-Start
    -- Jede Abfrage beantwortet der "Server" mit dem passenden Ereignis
    local handled = 0
    while handled < #Stub.queries and handled < 50 do
        handled = handled + 1
        local q = Stub.queries[handled]
        Stub.Fire(q.kind == "log" and "GUILDBANKLOG_UPDATE" or "GUILDBANKBAGSLOTS_CHANGED")
    end
    Stub.Fire("GUILDBANKFRAME_CLOSED")
end

-- ------------------------------------------------------------
-- Gildenbank-Scan (Grundlage fuer den Export)
-- ------------------------------------------------------------
test("Scan speichert die Vorgaenge", function()
    RunBankVisit()
    eq(#DB.GetGuildData().transactions, 4, "Vorgaenge")
end)

test("Zweiter Besuch ohne neue Vorgaenge speichert nichts doppelt", function()
    RunBankVisit()
    eq(#DB.GetGuildData().transactions, 4, "Vorgaenge")
end)

test("Bestand nach dem Scan", function()
    eq(DB.GetInventoryCount(2770), 35, "Kupfererz")
    eq(DB.GetInventoryCount(13444), 12, "Grosser Manatrank")
end)

-- Sammelliste: Gegenstand, freier Text und ein dem Client unbekannter Gegenstand
DB.AddCollectEntry({ itemID = 2770, itemName = "Kupfererz", target = 200, note = "für Fach 2" })
DB.AddCollectEntry({ itemName = "Gold für Fach 3", target = 1 })
DB.AddCollectEntry({ itemID = 99999, itemName = "Unbekanntes Ding", target = 5 })

-- ------------------------------------------------------------
-- Gegenstandsklasse (seit 1.4.2)
-- ------------------------------------------------------------
test("ClassOf liefert classID und subclassID aus GetItemInfoInstant", function()
    local c, s = Web.ClassOf(2770)
    eq(c, 7, "classID Kupfererz")
    eq(s, 7, "subclassID Kupfererz")
    c, s = Web.ClassOf(19019)
    eq(c, 2, "classID Waffe")
    eq(s, 7, "subclassID Waffe")
    c, s = Web.ClassOf(13444)
    eq(c, 0, "classID 0 (Verbrauchbar) ist ein echter Wert")
    eq(s, 1, "subclassID Trank")
end)

test("ClassOf ohne Daten: nil statt geraten", function()
    eq(Web.ClassOf(99999), nil, "unbekannter Gegenstand")
    eq(Web.ClassOf(0), nil, "ItemID 0")
    eq(Web.ClassOf(nil), nil, "keine ItemID")
    local saved = C_Item.GetItemInfoInstant
    C_Item.GetItemInfoInstant = nil
    eq(Web.ClassOf(2770), nil, "Client ohne GetItemInfoInstant")
    C_Item.GetItemInfoInstant = function() error("kaputt") end
    eq(Web.ClassOf(2770), nil, "Fehler in der API")
    C_Item.GetItemInfoInstant = saved
end)

-- ------------------------------------------------------------
-- Webseiten-Code (GKW1)
-- ------------------------------------------------------------
local function irows(rows)
    local t = {}
    for _, r in ipairs(rows) do if r[1] == "I" then t[tonumber(r[2])] = r end end
    return t
end

local codeWithClass, codeWithout

test("GKW1-Code: Huelle, Pruefsumme, Kopfzeile", function()
    local code, counts = Web.BuildCode("alles")
    codeWithClass = code
    local rows = rowsOf(decodeCode(code))
    eq(rows[1][1], "H", "erste Zeile")
    eq(rows[1][2], "1", "Formatversion bleibt 1")
    eq(rows[1][7], "1.4.2", "Addon-Version")
    eq(rows[1][11], tostring(Stub.interface), "Interface")
    eq(counts.t, 4, "T")
end)

test("I-Zeilen: Qualitaet, classID, subclassID", function()
    local I = irows(rowsOf(decodeCode(codeWithClass)))
    eq(table.concat(I[2770], "\t"), "I\t2770\t1\t7\t7", "Kupfererz")
    eq(table.concat(I[19019], "\t"), "I\t19019\t5\t2\t7", "Donnerzorn")
    eq(table.concat(I[2589], "\t"), "I\t2589\t1\t7\t5", "Leinenstoff")
    eq(table.concat(I[13444], "\t"), "I\t13444\t1\t0\t1", "Manatrank (Klasse 0)")
    eq(I[99999], nil, "unbekannter Gegenstand ohne Seltenheit: keine I-Zeile")
end)

test("I-Zeilen zaehlen nicht in E", function()
    local rows = rowsOf(decodeCode(codeWithClass))
    local n = { T = 0, S = 0, C = 0, I = 0 }
    local e
    for _, r in ipairs(rows) do
        if n[r[1]] then n[r[1]] = n[r[1]] + 1 end
        if r[1] == "E" then e = r end
    end
    truthy(n.I > 0, "I-Zeilen vorhanden")
    eq(e[2], tostring(n.T), "E: T")
    eq(e[3], tostring(n.S), "E: S")
    eq(e[4], tostring(n.C), "E: C")
    eq(#e, 4, "E hat genau drei Zahlen")
    eq(rows[#rows][1], "E", "E ist die letzte Zeile")
end)

test("Ohne GetItemInfoInstant-Daten: I-Zeilen wie in 1.4.1", function()
    Stub.noInstant = true
    codeWithout = Web.BuildCode("alles")
    Stub.noInstant = false
    for _, r in ipairs(rowsOf(decodeCode(codeWithout))) do
        if r[1] == "I" then eq(#r, 3, "Felder in " .. table.concat(r, " ")) end
    end
end)

test("Nutzlast enthaelt keine WoW-Steuerzeichen", function()
    local payload = decodeCode(codeWithClass)
    truthy(not payload:find("|", 1, true), "kein |")
    truthy(not payload:find("\r", 1, true), "kein CR")
end)

-- Codes fuer den Gegentest mit dem Parser der Webseite (tests/check_gkw.py)
if os.getenv("GK_CODES_OUT") then
    local f = assert(io.open(os.getenv("GK_CODES_OUT"), "a"))
    f:write(profile, "\tklassen\t", codeWithClass or "", "\n")
    f:write(profile, "\tohne\t", codeWithout or "", "\n")
    f:close()
end

-- ------------------------------------------------------------
-- Befehle
-- ------------------------------------------------------------
test("/gkeep webseite oeffnet das Fenster mit dem Code", function()
    if _G.GrindkeepTextWindow then _G.GrindkeepTextWindow:Hide() end
    SlashCmdList.GRINDKEEP("webseite alles")
    local win = _G.GrindkeepTextWindow
    truthy(win and win:IsShown(), "Fenster sichtbar")
    truthy(win.edit:GetText():sub(1, 5) == "GKW1:", "Code im Fenster")
end)

test("Alle Befehle laufen ohne Lua-Fehler", function()
    for _, cmd in ipairs({ "", "stock", "stock scan", "missing", "min", "min 2770 100", "list",
        "player Krutolo Zitterhand", "tx Krutolo Zitterhand gold", "alt Twink = Krutolo Zitterhand",
        "unalt Twink", "banktab", "sammel", "bericht bestand", "search Kupfer", "loot recent",
        "loot check Kupfer", "import", "export", "style", "check", "lager", "namen", "webseite",
        "webseite 30", "webseite alles", "reset", "options", "help", "?" }) do
        local ok, err = pcall(SlashCmdList.GRINDKEEP, cmd)
        if not ok then error("/gkeep " .. cmd .. ": " .. tostring(err)) end
    end
end)

test("Allgemeiner Export baut alle Arten und Formate", function()
    local E = GrindkeepExport
    truthy(E and E.Kinds and E.Formats, "Export-Modul")
    for _, kind in ipairs(E.Kinds) do
        for _, format in ipairs(E.Formats) do
            local ok, chunks = pcall(E.Build, kind, format)
            truthy(ok, kind .. "/" .. format .. ": " .. tostring(chunks))
            truthy(type(chunks) == "table", kind .. "/" .. format)
        end
    end
end)

out:write(("[%s] %d bestanden, %d fehlgeschlagen\n"):format(profile, passed, failed))
os.exit(failed == 0 and 0 or 1)

--[[
    Laufzeit-Tests mit nachgebauter WoW-API.

    Aufruf (aus dem Hauptordner des Addons):
        lua5.1 tests/run.lua forever
        lua5.1 tests/run.lua retail
    oder alles zusammen: sh tests/run.sh

    Jedes Profil laeuft in einem eigenen Prozess, weil das Addon mit
    globalen Tabellen arbeitet.
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
local Names = GrindkeepNames
local Comm = GrindkeepComm
local BotExport = GrindkeepBotExport
local L = GrindkeepLocale

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

local function realmOf(name) return name .. "-" .. Stub.realm end

-- ------------------------------------------------------------
-- Namen
-- ------------------------------------------------------------
test("Name ohne Realm bleibt vollstaendig (Leerzeichen)", function()
    local base, realm = Names.Split("Bobcation Immolation")
    eq(base, "Bobcation Immolation", "base")
    eq(realm, nil, "realm")
end)

test("Eigener Realm wird abgetrennt, Leerzeichen bleiben", function()
    local base, realm = Names.Split("Bobcation Immolation-Testrealm")
    eq(base, "Bobcation Immolation", "base")
    eq(realm, "Testrealm", "realm")
end)

test("Bindestrich im Nachnamen ist kein Realm", function()
    local base, realm = Names.Split("Anna Meier-Schulz")
    eq(base, "Anna Meier-Schulz", "base")
    eq(realm, nil, "realm")
    base, realm = Names.Split("Anna Meier-Schulz-Testrealm")
    eq(base, "Anna Meier-Schulz", "base mit Realm")
    eq(realm, "Testrealm", "realm")
end)

test("Fremder Realm bleibt Teil des Namens", function()
    local base, realm = Names.Split("Krutolo Zitterhand-Fremdrealm")
    eq(base, "Krutolo Zitterhand-Fremdrealm", "base")
    eq(realm, nil, "realm")
    eq(Names.Same("Krutolo Zitterhand", "Krutolo Zitterhand-Fremdrealm"), false, "Same")
end)

test("Verbundener Realm nur, wenn der Client ihn meldet", function()
    local base, realm = Names.Split("Krutolo Zitterhand-Nachbarrealm")
    if forever then
        eq(realm, nil, "realm (Forever ohne Liste)")
        eq(base, "Krutolo Zitterhand-Nachbarrealm", "base")
    else
        eq(realm, "Nachbarrealm", "realm")
        eq(base, "Krutolo Zitterhand", "base")
        eq(Names.Same("Krutolo Zitterhand-Testrealm", "Krutolo Zitterhand-Nachbarrealm"), false, "zwei Realms")
    end
end)

test("Name ohne Realm passt zu Name-EigenerRealm", function()
    eq(Names.Same("Bobcation Immolation", "Bobcation Immolation-Testrealm"), true, "Same")
    eq(Names.Base("Bobcation Immolation-Testrealm"), "Bobcation Immolation", "Base")
    eq(Names.Me(), realmOf(Stub.playerName), "Me")
end)

-- ------------------------------------------------------------
-- Vertrauen im Gilden-Abgleich (Comm.lua)
-- ------------------------------------------------------------
local function rosterName(name, realm)
    -- Forever: Roster ohne Realm (gemessen), Retail: immer mit Realm
    if forever then return name end
    return name .. "-" .. (realm or Stub.realm)
end

Stub.roster = {
    { name = rosterName("Krutolo Zitterhand"), rank = 1 },
    { name = rosterName("Anna Meier-Schulz"), rank = 0 },
    { name = rosterName("Niedrig Rang"), rank = 7 },
    { name = rosterName(Stub.playerName), rank = 0 },
    { name = rosterName("Doppel"), rank = 8 },
    { name = rosterName("Doppel", "Nachbarrealm"), rank = 0 },
}

local function altMsg(twink, main, sender)
    Comm._HandleAddonMessage("ALT:" .. twink .. "=" .. main, "GUILD", sender)
    return DB.GetMain(twink)
end

test("Zuordnung vom Offizier (Absender mit Realm) wird uebernommen", function()
    eq(altMsg("Twink Eins", "Krutolo Zitterhand", "Krutolo Zitterhand-Testrealm"), "Krutolo Zitterhand", "Main")
end)

test("Offizier mit Bindestrich-Nachnamen wird erkannt", function()
    eq(altMsg("Twink Zwei", "Anna Meier-Schulz", "Anna Meier-Schulz-Testrealm"), "Anna Meier-Schulz", "Main")
end)

test("Namensvetter von fremdem Realm wird abgewiesen", function()
    eq(altMsg("Twink Drei", "Krutolo Zitterhand", "Krutolo Zitterhand-Fremdrealm"), "Twink Drei", "Main")
end)

test("Niedriger Rang wird abgewiesen", function()
    eq(altMsg("Twink Vier", "Niedrig Rang", "Niedrig Rang-Testrealm"), "Twink Vier", "Main")
end)

test("Mehrdeutiger Name: im Zweifel weniger Vertrauen", function()
    -- Forever: zwei "Doppel" ohne Realm im Roster (Rang 8 und 0) - der
    -- niedrigere Rang zaehlt. Retail: Realm entscheidet.
    eq(altMsg("Twink Fuenf", "Doppel", "Doppel-Testrealm"), "Twink Fuenf", "eigener Realm, Rang 8")
    if not forever then
        eq(altMsg("Twink Sechs", "Doppel", "Doppel-Nachbarrealm"), "Doppel", "Nachbarrealm, Rang 0")
    end
end)

test("Eigenes Echo wird ignoriert", function()
    eq(altMsg("Twink Sieben", "Krutolo Zitterhand", realmOf(Stub.playerName)), "Twink Sieben", "Main")
end)

test("Eigene Zuordnung wird mit vollem Namen gesendet", function()
    Stub.sentAddon = {}
    SlashCmdList.GRINDKEEP("alt Mein Twink = Krutolo Zitterhand")
    eq(DB.GetMain("Mein Twink"), "Krutolo Zitterhand", "Main")
    eq(#Stub.sentAddon, 1, "gesendete Nachrichten")
    eq(Stub.sentAddon[1].msg, "ALT:Mein Twink=Krutolo Zitterhand", "Nachricht")
end)

-- ------------------------------------------------------------
-- Loot: Duplikate trotz unterschiedlicher Schreibweise erkennen
-- ------------------------------------------------------------
test("Loot-Duplikate: mit/ohne Realm gleich, Bindestrich-Nachnamen getrennt", function()
    DB.SetSetting("lootTrackingEnabled", true)
    local g = DB.GetGuildData()
    local before = #g.loot
    local function remote(recipient, ts)
        GrindkeepLoot.OnRemoteLoot({ ts = ts, itemID = 19019, itemLink = Stub.Link(19019), count = 1,
            recipient = recipient, reportedBy = "Krutolo Zitterhand" })
    end
    remote("Anna Meier-Schulz-Testrealm", Stub.now)
    remote("Anna Meier-Schulz", Stub.now + 10)    -- dieselbe Vergabe
    remote("Anna Meier-Krause", Stub.now + 20)    -- andere Person!
    eq(#g.loot - before, 2, "neue Loot-Eintraege")
end)

-- ------------------------------------------------------------
-- Bot-Export ohne Daten
-- ------------------------------------------------------------
test("Bot-Export ohne Bestand meldet den Grund", function()
    local text, why = BotExport.Build()
    eq(text, nil, "text")
    eq(why, "BOTEXPORT_NO_DATA", "Grund")
    truthy(L[why] ~= why, "Text zum Grund vorhanden")
end)

-- ------------------------------------------------------------
-- Gildenbank-Scan von Anfang bis Ende
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
Stub.bank.slots[2] = { { id = 2589, count = 40 }, { id = 2770, count = 3 } }

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

test("Scan speichert alle Vorgaenge mit vollen Namen", function()
    RunBankVisit()
    local g = DB.GetGuildData()
    eq(#g.transactions, 4, "Vorgaenge")
    local players = {}
    for _, tx in ipairs(g.transactions) do players[tx.player] = true end
    truthy(players["Krutolo Zitterhand"], "Krutolo Zitterhand")
    truthy(players["Anna Meier-Schulz"], "Anna Meier-Schulz")
end)

test("Zweiter Besuch ohne neue Vorgaenge speichert nichts doppelt", function()
    RunBankVisit()
    eq(#DB.GetGuildData().transactions, 4, "Vorgaenge")
end)

test("Neuer Vorgang beim naechsten Besuch wird erkannt", function()
    table.insert(Stub.bank.logs[1], { type = "deposit", name = "Niedrig Rang", id = 2770, count = 7, hours = 0 })
    RunBankVisit()
    eq(#DB.GetGuildData().transactions, 5, "Vorgaenge")
end)

test("Bestand nach dem Scan", function()
    eq(DB.GetInventoryCount(2770), 38, "Kupfererz gesamt")
    eq(DB.GetInventoryCount(2589), 40, "Leinenstoff")
    local e = DB.GetInventory().items[2770]
    eq(e.tabs[1], 35, "Kupfererz Fach 1")
    eq(e.tabs[2], 3, "Kupfererz Fach 2")
end)

-- ------------------------------------------------------------
-- Bot-Export
-- ------------------------------------------------------------
test("Adler-32 stimmt mit dem Referenzwert ueberein", function()
    eq(BotExport.Adler32("Wikipedia"), "11e60398", "Adler32(Wikipedia)")
    eq(BotExport.Adler32(""), "00000001", "Adler32(leer)")
end)

test("Bot-Export: Aufbau, Reihenfolge, Pruefsumme", function()
    local text, n = BotExport.Build({ now = Stub.now })
    eq(n, 4, "Zeilen")
    truthy(not text:find("|", 1, true), "kein | im Text")
    local lines = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    eq(#lines, 6, "Zeilen inkl. Kopf und END")
    eq(lines[1], "GRINDKEEP;1;" .. Stub.now .. ";" .. DB.GetInventory().scannedAt .. ";Die Grindgilde;Testrealm;4", "Kopf")
    eq(lines[2], "2770;Kupfererz;35;1", "Zeile 1")
    eq(lines[3], "19019;Donnerzorn Gesegnete Klinge;1;1", "Zeile 2 (Semikolon entfernt)")
    eq(lines[4], "2589;Leinenstoff;40;2", "Zeile 3")
    eq(lines[5], "2770;Kupfererz;3;2", "Zeile 4")
    local payload = table.concat(lines, "\n", 1, 5)
    eq(lines[6], "END;4;" .. BotExport.Adler32(payload), "END")
end)

test("Bot-Export: Parser liest den eigenen Text zurueck", function()
    local text = BotExport.Build({ now = Stub.now })
    local data, err = BotExport.Parse(text)
    truthy(data, "Parse: " .. tostring(err))
    eq(#data.rows, 4, "Zeilen")
    eq(data.guild, "Die Grindgilde", "Gilde")
    eq(data.rows[1].id, 2770, "erste ID")
    -- Windows-Zeilenenden und ein Code-Block-Rahmen aendern nichts am Inhalt
    local crlf = text:gsub("\n", "\r\n")
    truthy(BotExport.Parse(crlf), "CRLF")
end)

test("Bot-Export: veraenderte oder abgeschnittene Kopien fallen auf", function()
    local text = BotExport.Build({ now = Stub.now })
    local changed = text:gsub("2589;Leinenstoff;40;2", "2589;Leinenstoff;400;2")
    local data, err = BotExport.Parse(changed)
    eq(data, nil, "veraendert")
    eq(err, "checksum mismatch", "Grund")
    local cut = text:match("^(.*)\n[^\n]*$") -- END-Zeile fehlt
    data, err = BotExport.Parse(cut)
    eq(data, nil, "abgeschnitten")
end)

test("Bot-Export: Textfelder werden bereinigt", function()
    eq(BotExport.Clean("|cffa335ee|Hitem:1::|h[Klinge; scharf]|h|r"), "[Klinge scharf]", "Link")
    eq(BotExport.Clean("a\tb\nc|d"), "a b cd", "Steuerzeichen")
    eq(BotExport.Clean("Stahl|A:Professions-Icon-Quality-Tier3:17:17::1|a"), "Stahl", "Qualitaetssymbol")
end)

-- ------------------------------------------------------------
-- Slash-Befehle
-- ------------------------------------------------------------
test("/grindkeep ist als Alias registriert", function()
    eq(SLASH_GRINDKEEP1, "/gkeep", "1")
    eq(SLASH_GRINDKEEP2, "/grindkeep", "2")
end)

test("/gkeep bot oeffnet das Fenster mit markiertem Exporttext", function()
    local win = _G.GrindkeepTextWindow
    if win then win:Hide() end
    SlashCmdList.GRINDKEEP("bot")
    win = _G.GrindkeepTextWindow
    truthy(win and win:IsShown(), "Fenster sichtbar")
    eq(win.edit:GetText(), (BotExport.Build()), "Inhalt")
    win:Hide()
    SlashCmdList.GRINDKEEP("export bot")
    truthy(win:IsShown(), "auch ueber /gkeep export bot")
    truthy(win.edit:GetText():sub(1, 10) == "GRINDKEEP;", "Bot-Format")
end)

test("/gkeep export bleibt der Datenaustausch zwischen Nutzern", function()
    _G.GrindkeepTextWindow:Hide()
    SlashCmdList.GRINDKEEP("export")
    local t = _G.GrindkeepTextWindow.edit:GetText()
    truthy(t ~= "" and not t:find("GRINDKEEP;", 1, true), "Base64-Austausch")
end)

test("Chat-Ausgaben enthalten kein loses |", function()
    Stub.printed = {}
    SlashCmdList.GRINDKEEP("?") -- unbekannt: volle Befehlsliste
    SlashCmdList.GRINDKEEP("check")
    SlashCmdList.GRINDKEEP("lager")
    truthy(#Stub.printed > 20, "Ausgaben vorhanden")
    for _, line in ipairs(Stub.printed) do
        local plain = line:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h.-|h", "")
        if plain:find("|", 1, true) then error("| in: " .. line) end
    end
end)

test("Alle Befehle laufen ohne Lua-Fehler", function()
    for _, cmd in ipairs({ "", "stock", "stock scan", "missing", "min", "min 2770 100", "missing", "list",
        "player Krutolo Zitterhand", "tx Krutolo Zitterhand gold", "unalt Mein Twink", "banktab",
        "sammel", "bericht bestand", "search Kupfer", "loot recent", "loot check Kupfer", "import",
        "style", "reset", "options", "help" }) do
        local ok, err = pcall(SlashCmdList.GRINDKEEP, cmd)
        if not ok then error("/gkeep " .. cmd .. ": " .. tostring(err)) end
    end
end)

test("Allgemeiner Export baut alle Arten und Formate", function()
    for _, kind in ipairs(GrindkeepExport.Kinds) do
        for _, format in ipairs(GrindkeepExport.Formats) do
            local chunks = GrindkeepExport.Build(kind, format)
            truthy(type(chunks) == "table" and #chunks > 0, kind .. "/" .. format)
            for _, c in ipairs(chunks) do
                truthy(not c:find("|", 1, true), "kein | in " .. kind .. "/" .. format)
            end
        end
    end
end)

out:write(("[%s] %d bestanden, %d fehlgeschlagen\n"):format(profile, passed, failed))
os.exit(failed == 0 and 0 or 1)

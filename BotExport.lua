--[[
    Grindkeep - BotExport.lua

    Export des Gildenbank-Bestands als maschinenlesbarer Text fuer den
    Grindhub-Discord-Bot. Format: docs/export-format.md (Version 1).

      GRINDKEEP;1;<Exportzeit>;<Bestandszeit>;<Gilde>;<Realm>;<Zeilen>
      <ItemID>;<Name>;<Anzahl>;<Fach>
      ...
      END;<Zeilen>;<Adler-32 als 8 Hex-Zeichen>

    Warum Semikolon: "|" ist in WoW ein Steuerzeichen, ein Tabulator geht
    beim Kopieren aus dem Textfeld und beim Einfuegen in Discord leicht
    verloren. Semikolon, Zeilenumbrueche und WoW-Steuerzeichen werden
    deshalb aus allen Textfeldern entfernt.

    Warum Adler-32: laesst sich ohne Bit-Operationen rechnen (WoW-Lua und
    reines Lua 5.1) und steht in fast jeder Sprache fertig bereit (z.B.
    Python zlib.adler32). Die Pruefsumme erkennt abgeschnittene oder
    veraenderte Kopien, sie ist KEIN Schutz gegen Faelschung.

    Wie ueberall: WoW laesst Addons nicht in die Zwischenablage schreiben.
    Der Text steht markiert in einem Fenster, kopiert wird mit Strg+C.
    Aufruf: /gkeep bot (auch /grindkeep bot oder /gkeep export bot).
]]

local DB = _G.GrindkeepDatabase
local L = _G.GrindkeepLocale
local Names = _G.GrindkeepNames

local BotExport = {}
_G.GrindkeepBotExport = BotExport

BotExport.VERSION = 1
BotExport.MAGIC = "GRINDKEEP"
local SEP = ";"

-- Textfeld bereinigen: WoW-Steuerzeichen (Farben, Links, Symbole) weg,
-- dann alles, was das Format stoeren wuerde.
local function Clean(v)
    if v == nil then return "" end
    local s = tostring(v)
    s = s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
    s = s:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    s = s:gsub("|", "")
    s = s:gsub("[;\t\r\n%z\1-\31]", " ")
    s = s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")
    return s
end
BotExport.Clean = Clean

-- Adler-32 (RFC 1950) ueber die Bytes des Textes. Rueckgabe als 8
-- Hex-Zeichen, klein geschrieben. Bewusst in zwei 16-Bit-Haelften
-- formatiert: string.format("%x") mit Werten ueber 2^31 ist in WoW-Lua
-- nicht verlaesslich.
function BotExport.Adler32(text)
    local a, b = 1, 0
    for i = 1, #text do
        a = (a + text:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%04x%04x", b, a)
end

local function ItemName(e)
    local n = e.itemName
    if (not n or n == "") and type(e.itemLink) == "string" then
        n = e.itemLink:match("|h%[(.-)%]|h")
    end
    return Clean(n or "")
end

local function GuildName()
    local name = GetGuildInfo and GetGuildInfo("player")
    return type(name) == "string" and name or ""
end

-- Zeilen aus dem letzten Bestands-Scan: je Gegenstand und Fach eine Zeile,
-- sortiert nach Fach und Item-ID (gleiche Daten = gleicher Text).
function BotExport.Rows(inv)
    local rows = {}
    for itemID, e in pairs(inv and inv.items or {}) do
        local id = tonumber(itemID)
        if id then
            local name = ItemName(e)
            local anyTab = false
            for tab, n in pairs(e.tabs or {}) do
                n = math.floor(tonumber(n) or 0)
                if n > 0 then
                    anyTab = true
                    table.insert(rows, { id = id, name = name, count = n, tab = tonumber(tab) or 0 })
                end
            end
            -- Ohne Fachangabe (aeltere Daten): Fach 0 = unbekannt
            if not anyTab and (tonumber(e.count) or 0) > 0 then
                table.insert(rows, { id = id, name = name, count = math.floor(e.count), tab = 0 })
            end
        end
    end
    table.sort(rows, function(x, y)
        if x.tab ~= y.tab then return x.tab < y.tab end
        return x.id < y.id
    end)
    return rows
end

-- Kompletter Exporttext. Rueckgabe: text, Anzahl Zeilen - oder nil und
-- ein Locale-Schluessel mit dem Grund.
-- opts (fuer Tests): now, guild, realm
function BotExport.Build(opts)
    opts = opts or {}
    local inv = DB.GetInventory()
    if not inv or not inv.scannedAt then return nil, "BOTEXPORT_NO_DATA" end

    local rows = BotExport.Rows(inv)
    local header = table.concat({
        BotExport.MAGIC,
        tostring(BotExport.VERSION),
        tostring(math.floor(opts.now or DB.Now())),
        tostring(math.floor(inv.scannedAt)),
        Clean(opts.guild or GuildName()),
        Clean(opts.realm or (Names and Names.OwnRealm()) or ""),
        tostring(#rows),
    }, SEP)

    local lines = { header }
    for _, r in ipairs(rows) do
        lines[#lines + 1] = table.concat({ tostring(r.id), r.name, tostring(r.count), tostring(r.tab) }, SEP)
    end
    local payload = table.concat(lines, "\n")
    local trailer = table.concat({ "END", tostring(#rows), BotExport.Adler32(payload) }, SEP)
    return payload .. "\n" .. trailer, #rows
end

-- Gegenstueck fuer Tests und als Referenz fuer den Bot: prueft einen
-- Exporttext und liefert Kopf und Zeilen - oder nil und einen Fehlertext.
function BotExport.Parse(text)
    if type(text) ~= "string" then return nil, "no text" end
    local lines = {}
    for line in (text:gsub("\r\n", "\n") .. "\n"):gmatch("(.-)\n") do
        if line ~= "" then lines[#lines + 1] = line end
    end
    if #lines < 2 then return nil, "too short" end

    local function split(line)
        local f = {}
        for field in (line .. SEP):gmatch("(.-)" .. SEP) do f[#f + 1] = field end
        return f
    end

    local h = split(lines[1])
    if h[1] ~= BotExport.MAGIC then return nil, "no header" end
    local version = tonumber(h[2])
    if version ~= BotExport.VERSION then return nil, "unsupported version" end

    local t = split(lines[#lines])
    if t[1] ~= "END" then return nil, "no END line (truncated?)" end
    local payload = table.concat(lines, "\n", 1, #lines - 1)
    if BotExport.Adler32(payload) ~= (t[3] or ""):lower() then return nil, "checksum mismatch" end

    local rows = {}
    for i = 2, #lines - 1 do
        local f = split(lines[i])
        if #f ~= 4 then return nil, "bad row " .. i end
        local id, count, tab = tonumber(f[1]), tonumber(f[3]), tonumber(f[4])
        if not id or not count or not tab then return nil, "bad row " .. i end
        rows[#rows + 1] = { id = id, name = f[2], count = count, tab = tab }
    end
    local declared = tonumber(h[7])
    if declared ~= #rows or tonumber(t[2]) ~= #rows then return nil, "row count mismatch" end

    return {
        version = version,
        exportedAt = tonumber(h[3]),
        scannedAt = tonumber(h[4]),
        guild = h[5],
        realm = h[6],
        rows = rows,
    }
end

local function Print(msg) print("|cff2ecc71[Grindkeep]|r " .. tostring(msg)) end

-- Fenster mit dem markierten Text (Textfenster aus Comm.lua)
function BotExport.Show()
    local text, info = BotExport.Build()
    if not text then
        Print(L[info])
        return false
    end
    local inv = DB.GetInventory()
    Print(string.format(L["BOTEXPORT_DONE"], info, date(L["DATE_FORMAT"], inv.scannedAt)))
    if _G.GrindkeepComm and _G.GrindkeepComm.ShowTextWindow then
        _G.GrindkeepComm.ShowTextWindow(L["BOTEXPORT_TITLE"], text)
    end
    return true
end

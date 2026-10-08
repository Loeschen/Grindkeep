--[[
    Grindkeep - WebExport.lua  (seit 1.4.0)

    Code fuer die Gilden-Webseite: Gildenbank-Vorgaenge, Bestand und
    Sammelliste in EINEM kopierbaren Text. Ein Offizier fuegt ihn auf der
    Webseite unter "Leitung -> Gildenbank" ein. Die Webseite erkennt beim
    naechsten Einfuegen selbst, was sie schon kennt, und legt nichts doppelt an.

    Format (Version 1), damit Addon und Webseite dasselbe verstehen:

      GKW1:<Base64 der Nutzlast>:<Adler-32 der Nutzlast, 8 Hex-Zeichen>

    Nutzlast: UTF-8-Text, Zeilen mit "\n", Felder mit Tabulator getrennt.
      H  1  Gilde  Realm  Exporteur  Exportzeit  Addon-Version  seit  Bankgold  Bankgold-Zeit  Interface
      T  Zeit  Spieler  Art(item|gold)  Aktion  Fach  Fachname  ItemID  Menge  Kupfer  Itemname
      S  ItemID  Itemname  Gesamt  Bank  Lager-Twinks  Mindestbestand
      C  ID  ItemID  Name/Text  Ziel  Vorhanden  Erledigt(0|1)  Notiz
      I  ItemID  Qualitaet (0 grau, 1 weiss, 2 gruen, 3 blau, 4 lila, 5 orange,
         6 Artefakt, 7 Erbstueck)   - seit 1.4.1, je Gegenstand einmal, nur
         wenn bekannt. Aeltere Webseiten ignorieren unbekannte Zeilenarten.
         Seit 1.4.2 optional dahinter classID und subclassID aus
         C_Item.GetItemInfoInstant (Gegenstandsklasse/-unterklasse fuer die
         Kategorien der Webseite). Fehlen beide, wenn das Spiel sie nicht kennt.
      E  AnzahlT  AnzahlS  AnzahlC
    Zeiten: Unix-Sekunden (Serverzeit). Fehlende Zahlen: 0. Spielernamen roh,
    so wie das Bank-Log sie liefert (in WoW Forever mit Nachnamen).
    Tabulatoren und Zeilenumbrueche in Texten werden durch Leerzeichen ersetzt,
    WoW-Steuerzeichen (Farben, Links) entfernt.
]]

local DB = _G.GrindkeepDatabase
local L = _G.GrindkeepLocale

local WebExport = {}
_G.GrindkeepWebExport = WebExport

WebExport.FORMAT_VERSION = 1
local OVERLAP = 7 * 86400 -- "seit dem letzten Export" mit einer Woche Ueberlappung

local function Print(msg)
    print("|cff2ecc71[Grindkeep]|r " .. tostring(msg))
end

-- Text ohne WoW-Steuerzeichen und ohne Tabulator/Zeilenumbruch
local function Clean(text)
    if text == nil then return "" end
    text = tostring(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|H.-|h%[?(.-)%]?|h", "%1")
    text = text:gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = text:gsub("|", "/")
    text = text:gsub("[\t\r\n]", " ")
    return text
end

local function Num(v)
    v = tonumber(v)
    if not v then return "0" end
    return string.format("%d", math.floor(v + 0.5))
end

local function Line(fields)
    local out = {}
    for i, f in ipairs(fields) do out[i] = Clean(f) end
    return table.concat(out, "\t")
end

local function ItemNameOf(e)
    local n = e.itemName or (e.itemLink and e.itemLink:match("|h%[(.-)%]|h"))
    if not n and e.itemID then n = "Item " .. e.itemID end
    return n or ""
end

-- Seltenheit eines Gegenstands (0-7) oder nil. Erst die Spiel-API, dann die
-- Farbe im gespeicherten Link (alt: |cffa335ee, neu: |cnIQ4:).
local LINK_COLOR_QUALITY = {
    ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3,
    ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7,
}
function WebExport.QualityOf(itemID, itemLink)
    itemID = tonumber(itemID)
    local q
    if itemID and itemID > 0 then
        if C_Item and C_Item.GetItemQualityByID then
            local ok, v = pcall(C_Item.GetItemQualityByID, itemID)
            if ok then q = v end
        end
        if q == nil and GetItemInfo then
            local ok, _, _, v = pcall(GetItemInfo, itemID)
            if ok then q = v end
        end
    end
    if q == nil and type(itemLink) == "string" then
        q = tonumber(itemLink:match("|cnIQ(%d):"))
        if q == nil then
            local hex = itemLink:match("|c%x%x(%x%x%x%x%x%x)")
            q = hex and LINK_COLOR_QUALITY[hex:lower()]
        end
    end
    q = tonumber(q)
    if q and q >= 0 and q <= 8 then return math.floor(q) end
    return nil
end

-- Gegenstandsklasse und -unterklasse (seit 1.4.2) oder nil. GetItemInfoInstant
-- braucht keine Serverabfrage. Neuere Clients: C_Item.GetItemInfoInstant,
-- aeltere: globales GetItemInfoInstant. Rueckgabe 6 und 7: classID, subClassID.
function WebExport.ClassOf(itemID)
    itemID = tonumber(itemID)
    if not itemID or itemID <= 0 then return nil end
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    if not f then return nil end
    local ok, _, _, _, _, _, classID, subClassID = pcall(f, itemID)
    classID, subClassID = tonumber(classID), tonumber(subClassID)
    if not ok or not classID or not subClassID or classID < 0 or subClassID < 0 then return nil end
    return math.floor(classID), math.floor(subClassID)
end

-- Adler-32 (ohne Bit-Operationen, laeuft in jedem Lua)
function WebExport.Adler32(s)
    local a, b = 1, 0
    for i = 1, #s do
        a = (a + s:byte(i)) % 65521
        b = (b + a) % 65521
    end
    return string.format("%08x", b * 65536 + a)
end

-- Baut die Nutzlast. mode: nil = seit dem letzten Export, "alles"/"all" = alles,
-- Zahl = die letzten n Tage. Rueckgabe: payload, Zaehler, Beschreibung, sinceTs
function WebExport.BuildPayload(mode)
    local g = DB.GetGuildData()
    if not g then return nil end
    local now = DB.Now()

    local sinceTs, label = 0, L["WEB_ALL"]
    local m = mode and tostring(mode):lower() or nil
    local days = m and tonumber(m)
    if days and days > 0 then
        sinceTs, label = now - days * 86400, string.format(L["WEB_DAYS"], days)
    elseif m == "alles" or m == "all" then
        sinceTs, label = 0, L["WEB_ALL"]
    elseif g.lastWebExportTs then
        sinceTs, label = math.max(0, g.lastWebExportTs - OVERLAP), L["WEB_SINCE_LAST"]
    end

    local guild = GetGuildInfo and GetGuildInfo("player") or ""
    local realm = GetNormalizedRealmName and GetNormalizedRealmName() or ""
    local me = UnitName and UnitName("player") or ""
    local version = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Grindkeep", "Version"))
        or (GetAddOnMetadata and GetAddOnMetadata("Grindkeep", "Version")) or "?"
    local interface = GetBuildInfo and select(4, GetBuildInfo()) or 0

    local lines = {}
    local seen, order = {}, {} -- Gegenstaende fuer die I-Zeilen (Seltenheit)
    local function Remember(itemID, itemLink)
        itemID = tonumber(itemID)
        if not itemID or itemID <= 0 then return end
        if not seen[itemID] then seen[itemID] = { link = itemLink }; table.insert(order, itemID)
        elseif itemLink and not seen[itemID].link then seen[itemID].link = itemLink end
    end
    table.insert(lines, Line({ "H", WebExport.FORMAT_VERSION, guild, realm, me, Num(now), version, Num(sinceTs),
        g.bankMoney and Num(g.bankMoney) or "", Num(g.bankMoneyAt), Num(interface) }))

    -- Vorgaenge (chronologisch)
    local nT = 0
    for _, tx in ipairs(g.transactions or {}) do
        if (tonumber(tx.ts) or 0) >= sinceTs and not (DB.IsGhostRecord and DB.IsGhostRecord(tx)) then
            local action = tx.action == "withdrawal" and "withdraw" or tx.action
            table.insert(lines, Line({ "T", Num(tx.ts), tx.player or "", tx.kind or "", action or "",
                Num(tx.tab), tx.tabName or "", Num(tx.itemID), Num(tx.count), Num(tx.amount),
                tx.kind == "item" and ItemNameOf(tx) or "" }))
            if tx.kind == "item" then Remember(tx.itemID, tx.itemLink) end
            nT = nT + 1
        end
    end

    -- Bestand (Gildenbank + Lager-Twinks), dazu Mindestbestaende
    local mins = DB.GetMinimums and DB.GetMinimums() or {}
    local listed, nS = {}, 0
    for _, e in ipairs(DB.GetCombinedInventory and DB.GetCombinedInventory("all") or {}) do
        local min = mins[e.itemID] and mins[e.itemID].count or 0
        table.insert(lines, Line({ "S", Num(e.itemID), ItemNameOf(e), Num(e.count), Num(e.bankCount),
            Num(e.storageCount), Num(min) }))
        listed[e.itemID] = true
        Remember(e.itemID, e.itemLink)
        nS = nS + 1
    end
    -- Mindestbestaende fuer Gegenstaende, von denen gar nichts da ist
    for itemID, mdata in pairs(mins) do
        if not listed[itemID] and type(mdata) == "table" then
            table.insert(lines, Line({ "S", Num(itemID), mdata.itemName or ("Item " .. tostring(itemID)), "0", "0", "0",
                Num(mdata.count) }))
            Remember(itemID, mdata.itemLink)
            nS = nS + 1
        end
    end

    -- Sammelliste (offen und erledigt)
    local nC = 0
    for _, e in ipairs(DB.GetCollectList and DB.GetCollectList(true) or {}) do
        table.insert(lines, Line({ "C", Num(e.id), Num(e.itemID), ItemNameOf(e), Num(e.target), Num(e.have),
            e.done and "1" or "0", e.note or "" }))
        Remember(e.itemID, e.itemLink)
        nC = nC + 1
    end

    -- Seltenheit je Gegenstand (seit 1.4.1), damit die Webseite die Namen
    -- in der passenden Farbe zeigen kann; seit 1.4.2 dahinter Klasse und
    -- Unterklasse fuer die Kategorien. Ohne bekannte Seltenheit keine Zeile:
    -- ein leeres Feld laese die Webseite als 0 (grau).
    for _, itemID in ipairs(order) do
        local q = WebExport.QualityOf(itemID, seen[itemID].link)
        if q then
            local fields = { "I", Num(itemID), Num(q) }
            local classID, subClassID = WebExport.ClassOf(itemID)
            if classID then
                fields[4], fields[5] = Num(classID), Num(subClassID)
            end
            table.insert(lines, Line(fields))
        end
    end

    table.insert(lines, Line({ "E", Num(nT), Num(nS), Num(nC) }))
    return table.concat(lines, "\n"), { t = nT, s = nS, c = nC }, label, sinceTs
end

function WebExport.BuildCode(mode)
    local payload, counts, label, sinceTs = WebExport.BuildPayload(mode)
    if not payload then return nil end
    local enc = _G.GrindkeepComm and _G.GrindkeepComm._Base64Encode
    if not enc then return nil end
    return "GKW1:" .. enc(payload) .. ":" .. WebExport.Adler32(payload), counts, label, sinceTs
end

function WebExport.Show(mode)
    local code, counts, label = WebExport.BuildCode(mode)
    if not code then
        Print(L["WEB_NO_GUILD"])
        return
    end
    local g = DB.GetGuildData()
    if g then g.lastWebExportTs = DB.Now() end
    if _G.GrindkeepComm and _G.GrindkeepComm.ShowTextWindow then
        _G.GrindkeepComm.ShowTextWindow(L["WEB_TITLE"], code)
    end
    Print(string.format(L["WEB_DONE"], counts.t, label, counts.s, counts.c))
end

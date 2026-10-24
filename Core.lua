--[[
    Grindkeep - Core.lua

    Verbindet die Blizzard-Gildenbank-API mit dem Datenmodell aus
    Database.lua: Event-Handling, Scan-Ablaufsteuerung und der
    asynchrone Item-Info-Cache.

    Aenderungen gegenueber der vorherigen Fassung (siehe Anforderungen):

    1) State-Machine statt fixem Timer:
       Es gibt KEIN C_Timer.After(0.6) mehr zwischen den Abfragen. Der
       Ablauf ist rein event-getrieben: QueryGuildBankLog(tab) ->
       warten auf GUILDBANKLOG_UPDATE -> erst dann auslesen -> naechster
       Tab. Nur falls der Server das Event gar nicht sendet (Absicherung
       gegen Verlust/Verschlucken), greift pro Tab ein Fallback-Timeout
       von TIMEOUT_SECONDS = 2.0s, der den aktuellen Schritt trotzdem
       verarbeitet, statt den Scan haengen zu lassen. Bei einer
       langsamen, aber grundsaetzlich funktionierenden Antwort (z.B. zu
       Raidzeiten) wartet die State-Machine dagegen so lange wie noetig
       auf das echte Event, statt verfrueht mit veralteten Daten zu lesen.

    2) Abgleich (seit 1.0):
       Blizzards Log hat keine Transaktions-IDs und nennt die Zeit nur
       relativ ("vor 3 Stunden"). Jeder sichtbare Eintrag bekommt deshalb
       einen Inhalts-Schluessel (Aktion, Spieler, Item/Betrag, Menge) und
       einen ungefaehren absoluten Zeitpunkt. Neue Eintraege werden in
       zwei Stufen erkannt (siehe ReconcileLog):
       a) Vergleich mit dem letzten bestaetigten Scan desselben Logs: das
          Ende des alten Stands muss mit dem Anfang des neuen
          uebereinstimmen, was danach kommt, ist neu.
       b) Alles, was a) nicht erklaert, wird gegen die gespeicherten Daten
          geprueft (gleicher Inhalt, passende Zeit, jeder gespeicherte
          Eintrag nur einmal) - so entsteht auch nach einem Import, beim
          allerersten Scan oder nach einem Timeout nichts doppelt.
       Ein leerer oder veralteter Lesevorgang veraendert den
       Vergleichsstand nicht. Die fruehere Variante verglich reine
       Textlisten inklusive Zeitangabe; dabei wurde das Geld-Log nach einer
       vollen Stunde doppelt gespeichert und nach einem leeren
       Lesevorgang gingen Eintraege verloren.
       Grenze ohne IDs: Faellt ein Vorgang heraus und kommt in derselben
       Stunde ein exakt gleicher hinzu, sieht das Log vorher und nachher
       gleich aus - das ist nicht unterscheidbar.

    - Async Item-Cache bleibt unveraendert: GetItemInfo() liefert fuer
      dem Client unbekannte Items zunaechst nil. Solche Eintraege werden
      ohne Item-Name/-Typ gespeichert und ihre interne ID in
      Database.pendingItems[itemID] vermerkt; trifft
      GET_ITEM_INFO_RECEIVED ein, werden alle wartenden Eintraege
      nachtraeglich angereichert (Database.EnrichItem).
]]

local DB = _G.GrindkeepDatabase
local L = _G.GrindkeepLocale
local MAX_LOG = MAX_GUILDBANK_TRANSACTIONS or 25
local TIMEOUT_SECONDS = 2.0 -- Fallback pro Tab, falls GUILDBANKLOG_UPDATE ausbleibt

local function Print(msg)
    print("|cff2ecc71[Grindkeep]|r " .. tostring(msg))
end

-- ============================================================
-- Zeitstempel-Naeherung
-- ============================================================
-- GetGuildBankTransaction/-MoneyTransaction liefern nur eine relative
-- "vor X Jahren/Monaten/Tagen/Stunden"-Angabe, keine absolute Zeit.
-- Fuer Sortierung/Anzeige reicht eine grobe Umrechnung auf einen
-- Unix-Timestamp; exakt auf die Minute ist das nicht.
local function ApproxTimestamp(years, months, days, hours)
    return DB.Now()
        - (years or 0) * 31536000
        - (months or 0) * 2592000
        - (days or 0) * 86400
        - (hours or 0) * 3600
end

-- ============================================================
-- Inhalts-Fingerprint (fuer den Positionsvergleich, siehe unten -
-- KEIN globaler Dedup-Schluessel mehr, siehe Database.lua)
-- ============================================================
local function Fingerprint(...)
    local parts = {}
    for _, v in ipairs({ ... }) do
        table.insert(parts, tostring(v))
    end
    return table.concat(parts, "|")
end

local function ItemIdFromLink(itemLink)
    if not itemLink then return nil end
    local id = itemLink:match("item:(%d+)")
    return id and tonumber(id)
end

-- ============================================================
-- Gueltigkeitspruefung eines Log-Eintrags
--
-- HINTERGRUND (Live-Fund Retail, 21.09.2026): Beim Scan einer Gilde mit
-- mehreren Faechern, in denen seit Monaten nichts passiert ist (Log also
-- leer), lieferte GetGuildBankTransaction KEIN nil als Typ, sondern
-- Eintraege ganz ohne Inhalt - kein Spielername, kein Item, keine
-- Zeitangabe. Die Schleife lief deshalb nicht wie vorgesehen aus,
-- sondern erzeugte Geister-Eintraege ("Unbekannt", -0x, absurde
-- Zeitangaben wie "vor 20717 Tagen" = Zeitstempel 0) fuer Fach 4-6.
--
-- Die genaue Ursache ist NICHT bestaetigt - plausibel ist, dass der
-- Server das Log dieser Faecher noch gar nicht geliefert hatte und der
-- Client solange Platzhalter zurueckgibt. Unabhaengig davon gilt die
-- Regel unten, deshalb wird hier nicht weiter spekuliert.
--
-- Ein echter Gildenbank-Eintrag hat IMMER einen Spielernamen (das Log
-- haelt fest, wer etwas getan hat). Ein Eintrag ganz ohne Namen UND
-- ohne Item ist also nie ein echter Vorgang, sondern Muell - der wird
-- hier verworfen, statt ihn in die Datenbank zu schreiben.
-- ============================================================
-- Nachtrag 1.3.1 (Live-Fund Retail, 30.09.2026): Die Platzhalter haben
-- teils doch einen "Itemlink" (ohne gueltige Item-ID, Menge 0, rotes
-- Fragezeichen) und eine Zeitangabe um 1970 ("vor 20725 Tagen"). Deshalb
-- zaehlt ohne Spielernamen nur ein Eintrag mit echter Item-ID UND Menge,
-- und Zeitangaben von mehr als 30 Jahren sind nie echt.
local function IsUsableEntry(name, itemLink, count, years)
    if tonumber(years) and tonumber(years) > 30 then return false end
    if name and name ~= "" then return true end
    local id = ItemIdFromLink(itemLink)
    if id and id > 0 and (tonumber(count) or 0) > 0 then return true end
    return false
end

-- ============================================================
-- Kompatibilitaets-Wrapper: der In-Game-Test hat gezeigt, dass der
-- alte globale GetItemInfo() in WoW Forever nicht mehr existiert
-- ("attempt to call a nil value") - nur noch die namespaced Variante
-- C_Item.GetItemInfo() ist vorhanden. Ueber diesen Wrapper laeuft
-- beides defensiv, falls sich das nochmal aendert.
-- ============================================================
local function GetItemInfoCompat(itemID)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemID)
    elseif GetItemInfo then
        return GetItemInfo(itemID)
    end
    return nil
end

-- ============================================================
-- Abgleich sichtbarer Log-Eintraege mit den gespeicherten Daten
-- ============================================================

-- Wie weit darf die errechnete Zeit eines Eintrags zwischen zwei Scans
-- auseinanderliegen? Die Stundenangabe ist abgerundet (bis zu 1 Stunde
-- Unterschied). Monate und Jahre rechnet Grindkeep nur naeherungsweise um
-- (30 bzw. 365 Tage) - wie der Server sie zaehlt, ist nicht bekannt.
-- Deshalb waechst die Toleranz bei alten Eintraegen mit ihrem Alter.
local function TimeTolerance(ageSeconds)
    ageSeconds = ageSeconds or 0
    if ageSeconds >= 28 * 86400 then
        return math.max(3 * 86400, math.floor(ageSeconds * 0.1))
    end
    return 5400
end

local function KeyName(name)
    if name == nil or name == "" or name == "?" or name == "Unbekannt" then return "" end
    return name
end

local function ItemKeyOf(itemID, itemLink)
    if itemID then return "i" .. itemID end
    return itemLink or ""
end

-- Inhalts-Schluessel eines Vorgangs - bewusst OHNE Zeitangabe.
local function EntryKey(kind, action, player, itemKey, count, amount)
    if action == "withdrawal" then action = "withdraw" end
    if kind == "gold" then
        return table.concat({ "g", tostring(action), KeyName(player), tostring(amount or 0) }, "\031")
    end
    return table.concat({ "i", tostring(action), KeyName(player), itemKey or "", tostring(count or 0) }, "\031")
end

local function RecordKey(rec)
    return EntryKey(rec.kind, rec.action, rec.player, ItemKeyOf(rec.itemID, rec.itemLink), rec.count, rec.amount)
end

-- Zuordnung ueber Inhalt und Zeit (fuer Faelle ohne Vorwissen: erster
-- Scan, Import, Timeout). visible: Eintraege mit .key/.ts, beliebige
-- Reihenfolge. stored: gespeicherte Eintraege. Jeder gespeicherte Eintrag
-- wird hoechstens einmal zugeordnet, und zwar dem zeitlich naechsten -
-- mehrere gleiche Vorgaenge in derselben Stunde bleiben so einzeln.
-- Rueckgabe: Indizes (in visible) der Eintraege ohne Partner = neu.
-- keyFn/tolFn sind optional (Standard: Gildenbank).
local function FindNewEntries(visible, stored, now, keyFn, tolFn, skipIds)
    keyFn = keyFn or RecordKey
    tolFn = tolFn or TimeTolerance
    local newIdx = {}
    if #visible == 0 then return newIdx end

    local byKey = {}
    for _, rec in ipairs(stored) do
        if not (skipIds and rec.id and skipIds[rec.id]) then
            local k = keyFn(rec)
            byKey[k] = byKey[k] or {}
            table.insert(byKey[k], { ts = rec.ts or 0, id = rec.id, used = false })
        end
    end

    -- Aelteste zuerst zuordnen: bei gleichen Vorgaengen derselben Stunde
    -- bleiben so die neuesten uebrig - genau die sind neu.
    local order = {}
    for i = 1, #visible do order[i] = i end
    table.sort(order, function(a, b)
        if visible[a].ts ~= visible[b].ts then return visible[a].ts < visible[b].ts end
        return a < b
    end)

    local isNew = {}
    for _, i in ipairs(order) do
        local e = visible[i]
        local tol = tolFn(now - e.ts)
        local best, bestDiff
        for _, cand in ipairs(byKey[e.key] or {}) do
            if not cand.used then
                local diff = math.abs(cand.ts - e.ts)
                if diff <= tol and (not bestDiff or diff < bestDiff) then
                    best, bestDiff = cand, diff
                end
            end
        end
        if best then
            best.used = true
            e.matchedId = best.id
        else
            isNew[i] = true
        end
    end

    for i = 1, #visible do
        if isNew[i] then table.insert(newIdx, i) end
    end
    return newIdx
end

-- Abgleich zweier aufeinanderfolgender Scans desselben Logs. Das Log ist
-- ein Fenster ueber die letzten Vorgaenge: Seit dem letzten Scan faellt
-- vorne (alt) etwas heraus und hinten (neu) kommt etwas dazu. Gesucht ist
-- also die groesste Ueberlappung "Ende des letzten Scans = Anfang des
-- jetzigen". Anders als ein reiner Inhaltsvergleich erkennt das auch
-- einen neuen Vorgang, der einem gerade herausgefallenen gleicht.
-- base, vis: chronologisch (alt -> neu). Rueckgabe: Laenge der Ueberlappung.
local function AlignWithBaseline(base, vis, now)
    local maxK = math.min(#base, #vis)
    for k = maxK, 1, -1 do
        local offset = #base - k
        local ok = true
        for i = 1, k do
            local b, v = base[offset + i], vis[i]
            if b.key ~= v.key or math.abs((b.ts or 0) - v.ts) > TimeTolerance(now - v.ts) then
                ok = false
                break
            end
        end
        if ok then return k end
    end
    return 0
end

-- Fuer Comm.lua (Import/Loot), Database.lua (Zusammenfuehren) und Tests.
_G.GrindkeepMatcher = {
    FindNewEntries = FindNewEntries,
    AlignWithBaseline = AlignWithBaseline,
    EntryKey = EntryKey,
    RecordKey = RecordKey,
    TimeTolerance = TimeTolerance,
}

-- ------------------------------------------------------------
-- Reihenfolge des Logs
--
-- Ob Index 1 der neueste oder der aelteste Eintrag ist, ist nicht
-- dokumentiert. Grindkeep leitet es ab und merkt es sich:
--  - aus den Zeitangaben, sobald ein Log mehr als eine Stunde umfasst,
--  - sonst aus dem Vergleich mit dem letzten Scan: nur in der richtigen
--    Richtung passen alter und neuer Stand ueber viele Eintraege zusammen.
-- Solange es unbekannt ist, wird beim Vergleich mit dem letzten Scan
-- einfach beides versucht.
-- Innerhalb derselben Stunde bleibt es bei der Reihenfolge des Spiels -
-- die ist von Scan zu Scan stabil.
-- ------------------------------------------------------------
local function LearnOrderFromTimes(list)
    if #list < 2 then return end
    local first, last = list[1].ts, list[#list].ts
    if first > last + 3600 then
        GrindkeepDB.logNewestFirst = true
    elseif last > first + 3600 then
        GrindkeepDB.logNewestFirst = false
    end
end

local function Chrono(list, newestFirst)
    if not newestFirst then return list end
    local out = {}
    for i = #list, 1, -1 do table.insert(out, list[i]) end
    return out
end

-- Ein Log (Fach oder Geld) mit den gespeicherten Daten abgleichen und die
-- neuen Vorgaenge speichern.
-- raw: gelesene Eintraege in der Reihenfolge des Spiels, jeweils mit .key,
--      .ts und .record (fertiger Datensatz fuer die Datenbank)
-- confirmed: true, wenn der Server das Log gerade frisch geliefert hat
--      (false nach einem Timeout - dann kann es ein veralteter Stand sein)
local function ReconcileLog(targetKey, kind, tab, raw, confirmed)
    local g = DB.GetGuildData()
    if not g then return 0 end
    local now = DB.Now()

    -- Eintraege jenseits der Aufbewahrungsdauer gar nicht erst beachten,
    -- sonst wuerden sie nach dem Aufraeumen beim naechsten Scan wieder
    -- als neu gespeichert.
    local retention = tonumber(DB.GetSetting("retentionDays")) or 0
    local cutoff = retention > 0 and (now - retention * 86400) or nil
    local visRaw = {}
    for _, e in ipairs(raw) do
        if not cutoff or e.ts >= cutoff then table.insert(visRaw, e) end
    end
    if #visRaw == 0 then return 0 end -- leerer Lesevorgang: nichts aendern

    LearnOrderFromTimes(visRaw)
    local baseRaw = g.logBaseline[targetKey] or {}

    -- Vergleich mit dem letzten Scan, in der bekannten Richtung oder -
    -- solange unbekannt - in beiden, die mit der groesseren Ueberlappung zaehlt.
    local k, newestFirst = 0, GrindkeepDB.logNewestFirst
    if confirmed and #baseRaw > 0 then
        local directions = (newestFirst == nil) and { true, false } or { newestFirst }
        local best, bestDir, other = -1, nil, 0
        for _, dir in ipairs(directions) do
            local kd = AlignWithBaseline(Chrono(baseRaw, dir), Chrono(visRaw, dir), now)
            if kd > best then
                other = math.max(other, best)
                best, bestDir = kd, dir
            else
                other = math.max(other, kd)
            end
        end
        if newestFirst == nil and best >= 3 and other * 2 < best then
            GrindkeepDB.logNewestFirst = bestDir -- eindeutig: merken
        end
        -- Solange die Richtung unbekannt ist, nur eine klar ueberzeugende
        -- Ueberlappung verwenden - eine zufaellige kurze wuerde sonst alles
        -- andere als "neu" gelten lassen.
        if newestFirst ~= nil or (best >= 2 and other * 2 < best) then
            k, newestFirst = best, bestDir
        end
    end
    if newestFirst == nil then newestFirst = false end

    local vis = Chrono(visRaw, newestFirst)
    local base = Chrono(baseRaw, newestFirst)
    for i = 1, k do vis[i].id = base[#base - k + i].id end

    -- Was die Ueberlappung nicht erklaert, wird zusaetzlich gegen die
    -- gespeicherten Daten geprueft (z.B. per Import schon vorhanden, oder
    -- es gibt noch keinen Vergleichsstand). Bei vorhandener Ueberlappung
    -- zaehlen dabei nur Eintraege, die NICHT schon zum letzten Stand
    -- gehoerten - die sind ja bereits zugeordnet.
    local candidates = {}
    for i = k + 1, #vis do table.insert(candidates, vis[i]) end
    local skipIds
    if k > 0 then
        skipIds = {}
        for _, b in ipairs(base) do if b.id then skipIds[b.id] = true end end
    end
    local oldest = vis[1].ts
    for _, e in ipairs(vis) do if e.ts < oldest then oldest = e.ts end end
    local stored = DB.GetTransactionsForTarget(kind, tab, oldest - TimeTolerance(now - oldest))
    local newIdx = FindNewEntries(candidates, stored, now, nil, nil, skipIds)

    local isNew = {}
    for _, i in ipairs(newIdx) do isNew[i] = true end

    -- Chronologisch speichern (alt -> neu): nach Zeit, bei gleicher Zeit
    -- in Log-Reihenfolge.
    local order = {}
    for i = 1, #candidates do order[i] = i end
    table.sort(order, function(a, b)
        if candidates[a].ts ~= candidates[b].ts then return candidates[a].ts < candidates[b].ts end
        return a < b
    end)

    local added = 0
    for _, i in ipairs(order) do
        local e = candidates[i]
        if isNew[i] then
            local id = DB.AddTransaction(e.record)
            e.id = id
            if e.afterAdd then e.afterAdd(id) end
            added = added + 1
        else
            e.id = e.matchedId
        end
    end

    -- Neuen Vergleichsstand nur aus einer frischen Serverantwort ableiten
    -- (in der Reihenfolge des Spiels gespeichert).
    if confirmed then
        local newBase = {}
        for _, e in ipairs(visRaw) do
            table.insert(newBase, { key = e.key, ts = e.ts, id = e.id })
        end
        g.logBaseline[targetKey] = newBase
    end
    return added
end

-- ============================================================
-- Ein Tab: Item-Transaktionen einlesen
-- ============================================================
local function ProcessItemTab(tabIndex, confirmed)
    local g = DB.GetGuildData()
    if not g then return 0 end

    local tabName = GetGuildBankTabInfo and select(1, GetGuildBankTabInfo(tabIndex))
    if tabName and tabName ~= "" then g.tabNames[tabIndex] = tabName end
    tabName = g.tabNames[tabIndex]

    local raw = {}
    for i = 1, MAX_LOG do
        local ok, type_, name, itemLink, count, _, _, year, month, day, hour =
            pcall(GetGuildBankTransaction, tabIndex, i)

        if not ok then
            Print(string.format(L["CORE_ERR_TAB"], tabIndex, i, tostring(type_)))
            break
        end
        if type_ == nil then break end

        -- Platzhalter ohne Spieler und ohne Item gar nicht erst beachten
        -- (siehe IsUsableEntry oben).
        if IsUsableEntry(name, itemLink, count, year) then
            local itemID = ItemIdFromLink(itemLink)
            local ts = ApproxTimestamp(year, month, day, hour)
            local record = {
                ts = ts, player = name, kind = "item", action = type_,
                tab = tabIndex, tabName = tabName,
                itemLink = itemLink, itemID = itemID, count = count or 0,
            }
            local resolved = false
            if itemID then
                local itemName, _, itemQuality, _, _, itemType = GetItemInfoCompat(itemID)
                if itemName then
                    record.itemName, record.itemQuality, record.itemType = itemName, itemQuality, itemType
                    resolved = true
                end
            end
            table.insert(raw, {
                key = EntryKey("item", type_, name, ItemKeyOf(itemID, itemLink), count, nil),
                ts = ts,
                record = record,
                afterAdd = (itemID and not resolved) and function(id) DB.QueueItemLookup(itemID, id) end or nil,
            })
        end
    end

    return ReconcileLog("item:" .. tabIndex, "item", tabIndex, raw, confirmed)
end

-- ============================================================
-- Geld-Log einlesen
-- ============================================================
local function ProcessMoneyLog(confirmed)
    local raw = {}
    for i = 1, MAX_LOG do
        local ok, type_, name, amount, years, months, days, hours =
            pcall(GetGuildBankMoneyTransaction, i)

        if not ok then
            Print(string.format(L["CORE_ERR_MONEYLOG"], i, tostring(type_)))
            break
        end
        if type_ == nil then break end

        -- Ein Geld-Eintrag ohne Spielernamen und ohne Betrag ist kein
        -- echter Vorgang.
        if IsUsableEntry(name, nil, nil, years)
            or (amount and amount > 0 and not (tonumber(years) and tonumber(years) > 30)) then
            local ts = ApproxTimestamp(years, months, days, hours)
            table.insert(raw, {
                key = EntryKey("gold", type_, name, nil, nil, amount),
                ts = ts,
                record = { ts = ts, player = name, kind = "gold", action = type_, amount = amount or 0 },
            })
        end
    end

    return ReconcileLog("gold", "gold", nil, raw, confirmed)
end

-- ============================================================
-- Scan-Ablaufsteuerung: rein event-getriebene State Machine.
-- Ablauf je Ziel (Tab oder Geld-Log): Query abfeuern -> warten auf
-- GUILDBANKLOG_UPDATE -> auslesen -> naechstes Ziel. Der
-- OnUpdate-Handler ist NUR ein Fallback-Timeout, kein Taktgeber.
-- ============================================================
local scanQueue = {}
local scanning = false
local currentTarget = nil
local totalNewThisRun = 0
local timeSinceTarget = 0
local targetHandled = false -- verhindert Doppel-Verarbeitung bei Event+Timeout-Race

local AdvanceQueue -- Vorwaertsdeklaration

-- Ist die Gildenbank gerade geoeffnet? Ohne geoeffnete Bank liefert der
-- Server nichts Neues; ein Scan wuerde nur alte oder leere Daten lesen.
local bankOpen = false

-- Zusaetzlich das Blizzard-Fenster selbst pruefen - falls ein Client
-- keines der beiden Oeffnen-Ereignisse schickt, geht der Scan trotzdem.
local function IsBankOpen()
    if bankOpen then return true end
    local f = _G.GuildBankFrame
    return f ~= nil and f.IsShown ~= nil and f:IsShown() == true
end

local scanItemTabs = 0

local function FinishScan()
    scanning = false
    currentTarget = nil
    if DB.SetLastLogScan then DB.SetLastLogScan(scanItemTabs) end
    if _G.GrindkeepUI and _G.GrindkeepUI.Refresh then _G.GrindkeepUI.Refresh() end
    if DB.GetSetting("scanChatMessages") then
        Print(string.format(L["CORE_SCAN_DONE"], totalNewThisRun))
    end

    -- Direkt im Anschluss den Bestand erfassen (seit v0.8). Bewusst
    -- danach und nicht parallel: beides fragt denselben Server, und
    -- nacheinander bleibt nachvollziehbar, welcher Teil klemmt, falls
    -- etwas schiefgeht. Abschaltbar ueber die Einstellungen.
    if DB.GetSetting("autoStockScan")
        and _G.GrindkeepScanner and _G.GrindkeepScanner.StartInventoryScan then
        _G.GrindkeepScanner.StartInventoryScan()
    end
end

local function FireQuery(target)
    local numTabs = (GetNumGuildBankTabs and GetNumGuildBankTabs()) or 0
    if target.kind == "item" then
        if QueryGuildBankTabInfo then QueryGuildBankTabInfo(target.tab) end
        QueryGuildBankLog(target.tab)
    else
        -- Das Geld-Log hat einen festen Index hinter dem letzten MOEGLICHEN
        -- Fach (so fragt es auch Blizzards eigene Gildenbank ab), nicht
        -- hinter dem letzten gekauften. Die Konstante stammt aus dem
        -- Gildenbank-Modul, das bei geoeffneter Bank geladen ist.
        local maxTabs = MAX_GUILDBANK_TABS or math.max(numTabs, 8)
        QueryGuildBankLog(maxTabs + 1)
    end
end

AdvanceQueue = function()
    local target = table.remove(scanQueue, 1)
    if not target then
        FinishScan()
        return
    end

    currentTarget = target
    timeSinceTarget = 0
    targetHandled = false
    FireQuery(target)
    -- Kein Timer hier: wir warten jetzt einfach auf GUILDBANKLOG_UPDATE
    -- (oder den Fallback-Timeout im OnUpdate-Handler unten).
end

local function ProcessCurrentTarget(confirmed)
    if not currentTarget or targetHandled then return end
    targetHandled = true

    local n
    if currentTarget.kind == "item" then
        n = ProcessItemTab(currentTarget.tab, confirmed)
    else
        n = ProcessMoneyLog(confirmed)
    end
    totalNewThisRun = totalNewThisRun + n
    AdvanceQueue()
end

local function OnLogUpdate()
    if not scanning or not currentTarget then return end
    ProcessCurrentTarget(true)
end

local function StartScan()
    if not IsInGuild() then
        Print(L["CORE_NOT_IN_GUILD"])
        return
    end
    if not IsBankOpen() then
        Print(L["CORE_BANK_NOT_OPEN"])
        return
    end
    if scanning then
        Print(L["CORE_SCAN_RUNNING"])
        return
    end
    if not GetGuildBankTransaction or not GetGuildBankMoneyTransaction then
        Print(L["CORE_API_MISSING"])
        return
    end

    -- Kontostand der Gildenbank merken (fuer den Webseiten-Export, seit 1.4.0)
    do
        local g = DB.GetGuildData()
        local ok, money = pcall(function() return GetGuildBankMoney and GetGuildBankMoney() end)
        if g and ok and type(money) == "number" then
            g.bankMoney, g.bankMoneyAt = money, DB.Now()
        end
    end

    local numTabs = (GetNumGuildBankTabs and GetNumGuildBankTabs()) or 0
    scanQueue = {}
    for t = 1, numTabs do
        -- Faecher, die der eigene Rang nicht einsehen darf, gar nicht
        -- erst abfragen. Bewusst nur ueberspringen, wenn der Client
        -- AUSDRUECKLICH "nicht einsehbar" meldet - vorhandene Faecher mit
        -- leerem Log werden also ganz normal gescannt, dort faengt die
        -- Eintragspruefung (IsUsableEntry) die leeren Platzhalter ab.
        local skip = false
        if GetGuildBankTabInfo then
            local ok, _, _, isViewable = pcall(GetGuildBankTabInfo, t)
            if ok and isViewable == false then skip = true end
        end
        if not skip then
            table.insert(scanQueue, { kind = "item", tab = t })
        end
    end
    scanItemTabs = #scanQueue
    table.insert(scanQueue, { kind = "money" })

    totalNewThisRun = 0
    scanning = true
    if DB.GetSetting("scanChatMessages") then
        -- Anzahl der TATSAECHLICH gescannten Faecher melden, nicht die
        -- Gesamtzahl moeglicher Faecher - sonst liest sich "Scan ueber
        -- 6 Faecher" so, als gaebe es sechs, obwohl nur eines gekauft ist.
        Print(string.format(L["CORE_SCAN_START"], #scanQueue - 1))
    end
    AdvanceQueue()
end

-- ============================================================
-- Bestands-Scan (seit v0.8): liest den tatsaechlichen INHALT der
-- Faecher, nicht das Log.
--
-- Warum ueberhaupt zusaetzlich zum Log? Das Log zeigt nur die letzten
-- 25 Vorgaenge pro Fach und sagt nichts darueber, was gerade da ist.
-- Der Bestand ist dagegen jederzeit vollstaendig ablesbar und die
-- Grundlage fuer Mindestbestaende/Fehllisten.
--
-- Ablauf wie beim Log-Scan: QueryGuildBankTab(tab) -> warten auf
-- GUILDBANKBAGSLOTS_CHANGED -> Faecher auslesen -> naechstes Fach.
-- Fuer Faecher, die der Server nicht ausliefert, greift derselbe
-- Fallback-Timeout wie oben, damit der Scan nicht haengen bleibt.
-- ============================================================
local MAX_SLOTS = MAX_GUILDBANK_SLOTS_PER_TAB or 98

local invQueue = {}
local invScanning = false
local invTarget = nil
local invTimeSince = 0
local invHandled = false
local invAccum = nil
local invTabNames = nil
local invUnresolved = 0
local invTimedOut = nil -- [tabIndex] = true, wenn der Server das Fach nicht geliefert hat

local InvAdvance -- Vorwaertsdeklaration

local function ReadTabContents(tabIndex)
    if not GetGuildBankItemInfo then return end

    for slot = 1, MAX_SLOTS do
        local ok, texture, count, _, _, quality = pcall(GetGuildBankItemInfo, tabIndex, slot)
        if not ok then break end
        if texture and count and count > 0 then
            local link
            if GetGuildBankItemLink then
                local ok2, l = pcall(GetGuildBankItemLink, tabIndex, slot)
                if ok2 then link = l end
            end

            local itemID = ItemIdFromLink(link)
            if itemID then
                local entry = invAccum[itemID]
                if not entry then
                    entry = { count = 0, tabs = {} }
                    invAccum[itemID] = entry
                end
                entry.count = entry.count + count
                entry.itemLink = entry.itemLink or link
                entry.itemQuality = entry.itemQuality or quality
                entry.tabs[tabIndex] = (entry.tabs[tabIndex] or 0) + count
                if not entry.itemName then
                    entry.itemName = (GetItemInfoCompat(itemID))
                end
            else
                -- Item-Link (noch) nicht aufloesbar - ehrlich mitzaehlen
                -- statt stillschweigend zu verschlucken.
                invUnresolved = invUnresolved + 1
            end
        end
    end
end

local function FinishInventoryScan()
    invScanning = false
    invTarget = nil

    -- Faecher, die der Server nicht rechtzeitig geliefert hat, NICHT als
    -- leer werten: dafuer die Mengen aus dem letzten Stand uebernehmen.
    -- Sonst stuende nach einem Aussetzer ploetzlich alles auf der Fehlliste.
    local previous = DB.GetInventory()
    if previous and previous.items and next(invTimedOut or {}) then
        for itemID, old in pairs(previous.items) do
            for tabIndex in pairs(invTimedOut) do
                local n = old.tabs and old.tabs[tabIndex]
                if n and n > 0 then
                    local entry = invAccum[itemID]
                    if not entry then
                        entry = { count = 0, tabs = {}, itemLink = old.itemLink,
                                  itemName = old.itemName, itemQuality = old.itemQuality }
                        invAccum[itemID] = entry
                    end
                    entry.count = entry.count + n
                    entry.tabs[tabIndex] = (entry.tabs[tabIndex] or 0) + n
                end
            end
        end
    end

    local total = 0
    for _ in pairs(invAccum or {}) do total = total + 1 end
    DB.SetInventorySnapshot(invAccum or {}, invTabNames or {})

    if DB.GetSetting("scanChatMessages") then
        Print(string.format(L["CORE_STOCK_SCAN_DONE"], total))
        if invUnresolved > 0 then
            Print(string.format(L["CORE_STOCK_UNRESOLVED"], invUnresolved))
        end
    end

    -- Wenn Mindestbestaende hinterlegt sind: kurz melden, was fehlt.
    local missing = DB.GetStockList(true)
    if #missing > 0 then
        Print(string.format(L["CORE_STOCK_MISSING_HINT"], #missing))
    end

    if _G.GrindkeepUI and _G.GrindkeepUI.Refresh then
        _G.GrindkeepUI.Refresh()
    end
    if _G.GrindkeepStockUI and _G.GrindkeepStockUI.Refresh then
        _G.GrindkeepStockUI.Refresh()
    end
end

local function InvProcessCurrent(timedOut)
    if not invTarget or invHandled then return end
    invHandled = true
    if timedOut then
        invTimedOut[invTarget] = true
    else
        ReadTabContents(invTarget)
    end
    InvAdvance()
end

InvAdvance = function()
    local tabIndex = table.remove(invQueue, 1)
    if not tabIndex then
        FinishInventoryScan()
        return
    end

    invTarget = tabIndex
    invTimeSince = 0
    invHandled = false

    local name = GetGuildBankTabInfo and select(1, GetGuildBankTabInfo(tabIndex))
    if name and name ~= "" then invTabNames[tabIndex] = name end

    if QueryGuildBankTab then
        QueryGuildBankTab(tabIndex)
    else
        -- Ohne Query-Funktion bleibt nur, direkt zu lesen, was der
        -- Client schon zwischengespeichert hat.
        InvProcessCurrent()
    end
end

local function StartInventoryScan()
    if not IsInGuild() then
        Print(L["CORE_NOT_IN_GUILD"])
        return
    end
    if not IsBankOpen() then
        Print(L["CORE_BANK_NOT_OPEN"])
        return
    end
    if invScanning then
        Print(L["CORE_SCAN_RUNNING"])
        return
    end
    if not GetGuildBankItemInfo then
        Print(L["CORE_API_MISSING"])
        return
    end

    local numTabs = (GetNumGuildBankTabs and GetNumGuildBankTabs()) or 0
    invQueue = {}
    for t = 1, numTabs do
        local skip = false
        if GetGuildBankTabInfo then
            local ok, _, _, isViewable = pcall(GetGuildBankTabInfo, t)
            if ok and isViewable == false then skip = true end
        end
        if not skip then table.insert(invQueue, t) end
    end

    invAccum = {}
    invTabNames = {}
    invUnresolved = 0
    invTimedOut = {}
    invScanning = true

    if DB.GetSetting("scanChatMessages") then
        Print(string.format(L["CORE_STOCK_SCAN_START"], #invQueue))
    end
    InvAdvance()
end

-- Bank geschlossen, waehrend noch gescannt wird: sauber abbrechen, ohne
-- etwas zu speichern. Bereits verarbeitete Faecher bleiben erhalten, der
-- Bestand behaelt seinen letzten vollstaendigen Stand.
local function AbortScans()
    if scanning then
        scanning = false
        currentTarget = nil
        scanQueue = {}
    end
    if invScanning then
        invScanning = false
        invTarget = nil
        invQueue = {}
        invAccum = nil
    end
end

local function OnBagSlotsChanged()
    if not invScanning or not invTarget then return end
    InvProcessCurrent()
end

_G.GrindkeepScanner = {
    StartScan = StartScan,
    StartInventoryScan = StartInventoryScan,
}

-- ============================================================
-- Event-Handling
-- ============================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("GUILDBANKFRAME_OPENED")
frame:RegisterEvent("GUILDBANKLOG_UPDATE")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

-- Zusaetzliche Ausloeser fuer den automatischen Scan (Live-Fund Retail,
-- 21.09.2026: dort kam beim Oeffnen der Gildenbank offenbar kein
-- GUILDBANKFRAME_OPENED an, der Scan musste von Hand gestartet werden).
-- Moderne Clients melden das Oeffnen eines Bankiers stattdessen ueber
-- PLAYER_INTERACTION_MANAGER_FRAME_SHOW. Beide Wege sind registriert,
-- eine Sperre (autoScanArmed) verhindert doppelte Scans, falls ein
-- Client BEIDE Ereignisse schickt. RegisterEvent laeuft ueber pcall,
-- da ein Client, der ein Ereignis nicht kennt, sonst einen Fehler wirft.
pcall(frame.RegisterEvent, frame, "GUILDBANKBAGSLOTS_CHANGED") -- Bestands-Scan
pcall(frame.RegisterEvent, frame, "GUILDBANKFRAME_CLOSED")
pcall(frame.RegisterEvent, frame, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
pcall(frame.RegisterEvent, frame, "PLAYER_INTERACTION_MANAGER_FRAME_HIDE")

local GUILD_BANKER_INTERACTION = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.GuildBanker
local autoScanArmed = true -- true = fuer die naechste geoeffnete Bank noch nicht gescannt

local function OnBankOpened()
    bankOpen = true
end

local function OnBankClosed()
    bankOpen = false
    autoScanArmed = true
    AbortScans()
end

-- Rechtzeitig vor dem Ablauf pruefen: der Scan startet mit etwas
-- Verzoegerung, in der die Bank schon wieder zu sein kann.
local function StartScanIfOpen()
    if IsBankOpen() then StartScan() end
end

local function TriggerAutoScan()
    if not autoScanArmed then return end
    if not DB.GetSetting("autoScanOnOpen") then return end
    autoScanArmed = false
    -- Kurz warten: direkt im Moment des Oeffnens hat der Client die Logs
    -- noch nicht angefordert; der Scan wuerde sonst ins Leere laufen.
    if C_Timer and C_Timer.After then
        C_Timer.After(0.5, StartScanIfOpen)
    else
        StartScanIfOpen()
    end
end

-- Item-Infos, die beim letzten Mal nicht mehr eintrafen, erneut anfordern.
local function RequestPendingItems()
    local g = DB.GetGuildData()
    if not g or not (C_Item and C_Item.RequestLoadItemDataByID) then return end
    for itemID in pairs(g.pendingItems) do
        pcall(C_Item.RequestLoadItemDataByID, itemID)
    end
end

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "ADDON_LOADED" then
        local addonName = ...
        if addonName == "Grindkeep" then
            -- Erst jetzt sind die gespeicherten Daten geladen.
            local removed = DB.OnLoad()
            if removed and removed > 0 and DB.GetSetting("scanChatMessages") then
                Print(string.format(L["CORE_PRUNED"], removed))
            end
            -- Umstieg auf volle Namen (1.4.2): nicht eindeutige Twinks melden
            if DB.ambiguousAlts and #DB.ambiguousAlts > 0 then
                Print(string.format(L["CORE_ALTS_AMBIGUOUS"], table.concat(DB.ambiguousAlts, ", ")))
            end
            if _G.GrindkeepStyle then _G.GrindkeepStyle.Apply() end
            if _G.GrindkeepUI and _G.GrindkeepUI.ApplySavedSettings then
                _G.GrindkeepUI.ApplySavedSettings()
            end
        end
    elseif event == "PLAYER_LOGIN" then
        RequestPendingItems()
    elseif event == "GUILDBANKFRAME_OPENED" then
        OnBankOpened()
        TriggerAutoScan()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        local interactionType = ...
        -- Nur echte Gildenbank-Oeffnungen - fehlt die Kennung auf einem
        -- Client, bleibt es beim Ereignis GUILDBANKFRAME_OPENED.
        if GUILD_BANKER_INTERACTION ~= nil and interactionType == GUILD_BANKER_INTERACTION then
            OnBankOpened()
            TriggerAutoScan()
        end
    elseif event == "GUILDBANKFRAME_CLOSED" then
        OnBankClosed()
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        local interactionType = ...
        if GUILD_BANKER_INTERACTION ~= nil and interactionType == GUILD_BANKER_INTERACTION then
            OnBankClosed()
        end
    elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        OnBagSlotsChanged()
    elseif event == "GUILDBANKLOG_UPDATE" then
        OnLogUpdate()
    elseif event == "GET_ITEM_INFO_RECEIVED" then
        local itemID, success = ...
        if success and itemID then
            local itemName, itemLink, itemQuality, _, _, itemType = GetItemInfoCompat(itemID)
            if itemName then
                DB.EnrichItem(itemID, itemName, itemLink, itemQuality, itemType)
            end
        end
    end
end)

-- Fallback-Timeout: NUR falls GUILDBANKLOG_UPDATE fuer das aktuelle
-- Ziel nach TIMEOUT_SECONDS gar nicht eintrifft (Server verschluckt/
-- verliert das Event). Bei normaler, auch langsamer Serverantwort
-- innerhalb dieses Fensters greift stattdessen ganz normal OnLogUpdate.
frame:SetScript("OnUpdate", function(self, elapsed)
    -- Bestands-Scan: gleicher Fallback wie beim Log. Liefert der Server
    -- den Inhalt eines Fachs nicht, wird trotzdem gelesen, was der
    -- Client zwischengespeichert hat, statt haengen zu bleiben.
    if invScanning and invTarget and not invHandled then
        invTimeSince = invTimeSince + elapsed
        if invTimeSince >= TIMEOUT_SECONDS then
            InvProcessCurrent(true)
        end
    end

    if scanning and currentTarget and not targetHandled then
        timeSinceTarget = timeSinceTarget + elapsed
        if timeSinceTarget >= TIMEOUT_SECONDS then
            local targetLabel = currentTarget.kind == "item"
                and string.format(L["CORE_TIMEOUT_TAB"], currentTarget.tab)
                or L["CORE_TIMEOUT_MONEYLOG"]
            if DB.GetSetting("scanChatMessages") then
                Print(string.format(L["CORE_TIMEOUT"], targetLabel))
            end
            -- Trotzdem lesen, was der Client hat: durch den Abgleich mit den
            -- gespeicherten Daten kann ein veralteter Stand nichts doppelt
            -- eintragen, schlimmstenfalls kommt etwas erst beim naechsten Mal.
            ProcessCurrentTarget(false)
        end
    end
end)

-- ============================================================
-- Slash-Befehle (funktionieren auch ohne geladenes UI-Modul; ist
-- GrindkeepUI geladen, oeffnet/schliesst der Aufruf ohne Argument
-- stattdessen das Fenster)
-- ============================================================
local function FormatGold(copper)
    copper = copper or 0
    local neg = copper < 0
    copper = math.abs(copper)
    local str = string.format(L["CORE_GOLD_FORMAT"], math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100)
    return neg and ("-" .. str) or str
end

local function PrintList(sortBy)
    local list = DB.GetPlayerList(sortBy)
    if #list == 0 then
        Print(L["CORE_LIST_EMPTY"])
        return
    end
    Print(string.format(L["CORE_LIST_HEADER"], sortBy or "net"))
    for _, entry in ipairs(list) do
        Print(string.format(L["CORE_LIST_ROW"], entry.name, FormatGold(entry.net), entry.summary.itemDeposits, entry.summary.itemWithdrawals))
    end
end

local function PrintDetails(name)
    local d = name and DB.GetPlayerDetails(name)
    if not d or (not d.own and #d.twinks == 0) then
        Print(string.format(L["CORE_DETAILS_NONE"], tostring(name)))
        return
    end
    if d.isTwinkOf then
        Print(string.format(L["CORE_IS_TWINK_OF"], name, d.isTwinkOf))
    end
    if #d.twinks > 0 then
        Print(string.format(L["CORE_HAS_TWINKS"], name, table.concat(d.twinks, ", ")))
    end
    if d.own then
        Print(string.format(L["CORE_OWN_BALANCE"],
            FormatGold(d.own.goldDeposited), FormatGold(d.own.goldWithdrawn), d.own.itemDeposits, d.own.itemWithdrawals))
    end
    Print(string.format(L["CORE_AGGREGATED"],
        FormatGold(d.aggregated.goldDeposited), FormatGold(d.aggregated.goldWithdrawn),
        FormatGold(d.aggregated.goldDeposited - d.aggregated.goldWithdrawn)))
end

local function PrintTransactions(name, category)
    if not name then Print(L["CORE_TX_NEED_NAME"]); return end
    local txs = DB.GetPlayerTransactions(name, category)
    if #txs == 0 then
        Print(string.format(L["CORE_TX_NONE"], name, tostring(category or L["CORE_FILTER_ALL"])))
        return
    end
    Print(string.format(L["CORE_TX_HEADER"], name))
    for i = 1, math.min(10, #txs) do
        local tx = txs[i]
        if tx.kind == "gold" then
            Print(string.format(L["CORE_TX_GOLD_LINE"], tx.action, FormatGold(tx.amount)))
        else
            Print(string.format(L["CORE_TX_ITEM_LINE"], tostring(tx.tab), tx.action, tx.count or 0, tx.itemName or tx.itemLink or L["CORE_ITEM_INFO_PENDING"]))
        end
    end
end

-- ============================================================
-- Bestand / Mindestbestaende / Fehlliste (Chat-Ausgabe)
-- ============================================================
local function FormatStockLine(entry)
    local label = entry.itemLink or entry.itemName or ("Item " .. tostring(entry.itemID))
    return label
end

local function PrintStock(limit)
    local inv = DB.GetInventory()
    if not inv or not inv.scannedAt then
        Print(L["CORE_STOCK_NO_DATA"])
        return
    end

    local list = DB.GetInventoryList("count")
    if #list == 0 then
        Print(L["CORE_STOCK_EMPTY"])
        return
    end

    limit = tonumber(limit) or 20
    Print(string.format(L["CORE_STOCK_HEADER"], #list))
    for i = 1, math.min(limit, #list) do
        local e = list[i]
        Print(string.format(L["CORE_STOCK_LINE"], e.count, FormatStockLine(e)))
    end
    if #list > limit then
        Print(string.format(L["CORE_STOCK_MORE"], #list - limit))
    end
end

local function PrintMissing()
    local list = DB.GetStockList(true)
    if #list == 0 then
        local mins = DB.GetMinimums()
        if next(mins) == nil then
            Print(L["CORE_MIN_NONE"])
        else
            Print(L["CORE_MISSING_NONE"])
        end
        return
    end

    Print(L["CORE_MISSING_HEADER"])
    for _, e in ipairs(list) do
        Print(string.format(L["CORE_MISSING_LINE"], FormatStockLine(e), e.have, e.required, e.missing))
    end
end

-- "/gkeep min <Itemlink oder Item-ID> <Menge>"
-- Der Itemlink wird per Shift-Klick auf ein Item in die Chatzeile
-- eingefuegt; darin steckt die Item-ID, die wir hier herausziehen.
local function HandleMinCommand(rest)
    rest = rest or ""

    if rest == "" or rest:lower() == "list" then
        local mins = DB.GetMinimums()
        if next(mins) == nil then
            Print(L["CORE_MIN_NONE"])
            return
        end
        Print(L["CORE_MIN_HEADER"])
        for _, e in ipairs(DB.GetStockList(false)) do
            Print(string.format(L["CORE_MIN_LINE"], FormatStockLine(e), e.required, e.have))
        end
        return
    end

    local itemID = tonumber(rest:match("|Hitem:(%d+)"))
    -- "|cff..." (klassisch) und "|cnIQ4:" (neuere Clients)
    local itemLink = rest:match("(|c[^|]*|Hitem:.-|h.-|h|r)") or rest:match("(|Hitem:.-|h.-|h)")

    if not itemID then
        -- Kein Link angegeben: dann muss eine reine Item-ID kommen
        itemID = tonumber(rest:match("^(%d+)%s"))
    end

    local count = tonumber(rest:match("(%d+)%s*$"))

    if not itemID or not count then
        Print(L["CORE_MIN_USAGE"])
        return
    end

    local itemName = (GetItemInfoCompat(itemID))
    if DB.SetMinimum(itemID, count, itemName, itemLink) then
        if count == 0 then
            Print(string.format(L["CORE_MIN_REMOVED"], itemLink or itemName or itemID))
        else
            Print(string.format(L["CORE_MIN_SET"], itemLink or itemName or itemID, count))
        end
        if _G.GrindkeepUI and _G.GrindkeepUI.Refresh then _G.GrindkeepUI.Refresh() end
    else
        Print(L["CORE_MIN_USAGE"])
    end
end

-- ============================================================
-- Selbstdiagnose "/gkeep check"
--
-- Entstanden aus der Praxis: bei drei Fehlern an einem Abend war jedes
-- Mal die entscheidende Frage "welche Funktionen kennt dieser Client
-- ueberhaupt und was liefern sie gerade zurueck?". Statt das jedes Mal
-- von Hand zusammenzutippen, beantwortet dieser Befehl es direkt.
-- ============================================================
local function CheckLine(label, value)
    Print(string.format("  %s: %s", label, tostring(value)))
end

local function PrintCheck()
    Print(L["CORE_CHECK_HEADER"])

    CheckLine(L["CORE_CHECK_GUILD"], IsInGuild() and (DB.GuildKey() or "?") or L["CORE_CHECK_NO_GUILD"])

    local apis = {
        { "GetNumGuildBankTabs", GetNumGuildBankTabs },
        { "GetGuildBankTabInfo", GetGuildBankTabInfo },
        { "QueryGuildBankLog", QueryGuildBankLog },
        { "GetGuildBankTransaction", GetGuildBankTransaction },
        { "GetGuildBankMoneyTransaction", GetGuildBankMoneyTransaction },
        { "QueryGuildBankTab", QueryGuildBankTab },
        { "GetGuildBankItemInfo", GetGuildBankItemInfo },
        { "GetGuildBankItemLink", GetGuildBankItemLink },
    }
    local missingApis = {}
    for _, a in ipairs(apis) do
        if type(a[2]) ~= "function" then table.insert(missingApis, a[1]) end
    end
    if #missingApis == 0 then
        CheckLine(L["CORE_CHECK_APIS"], L["CORE_CHECK_ALL_PRESENT"])
    else
        CheckLine(L["CORE_CHECK_APIS"], L["CORE_CHECK_MISSING"] .. " " .. table.concat(missingApis, ", "))
    end

    local numTabs = (GetNumGuildBankTabs and GetNumGuildBankTabs()) or 0
    CheckLine(L["CORE_CHECK_TABS"], numTabs)

    for t = 1, numTabs do
        local name, _, isViewable
        if GetGuildBankTabInfo then
            local ok, a, b, c = pcall(GetGuildBankTabInfo, t)
            if ok then name, _, isViewable = a, b, c end
        end

        -- Erster Log-Eintrag des Fachs, sofern lesbar
        local firstEntry = "-"
        if GetGuildBankTransaction then
            local ok, type_, player = pcall(GetGuildBankTransaction, t, 1)
            if ok and type_ then
                firstEntry = string.format("%s / %s", tostring(type_), tostring(player))
            end
        end

        CheckLine(string.format(L["CORE_CHECK_TAB_LABEL"], t),
            string.format("%s - %s: %s - %s: %s",
                name or "?",
                L["CORE_CHECK_VIEWABLE"], tostring(isViewable),
                L["CORE_CHECK_FIRST_LOG"], firstEntry))
    end

    local inv = DB.GetInventory()
    if inv and inv.scannedAt then
        local count = 0
        for _ in pairs(inv.items) do count = count + 1 end
        CheckLine(L["CORE_CHECK_STOCK"], string.format(L["CORE_CHECK_STOCK_VALUE"], count, date(L["DATE_FORMAT"], inv.scannedAt)))
    else
        CheckLine(L["CORE_CHECK_STOCK"], L["CORE_STOCK_NO_DATA"])
    end

    local g = DB.GetGuildData()
    if g then
        CheckLine(L["CORE_CHECK_TX"], #g.transactions)
    end

    Print(L["CORE_CHECK_FOOTER"])
end

local function PrintHelp()
    Print(L["CORE_HELP_HEADER"])
    Print(L["CORE_HELP_TOGGLE"])
    Print(L["CORE_HELP_OPTIONS"])
    Print(L["CORE_HELP_SCAN"])
    Print(L["CORE_HELP_LIST"])
    Print(L["CORE_HELP_PLAYER"])
    Print(L["CORE_HELP_TX"])
    Print(L["CORE_HELP_ALT"])
    Print(L["CORE_HELP_UNALT"])
    Print(L["CORE_HELP_NAMES"])
    Print(L["CORE_HELP_WEB"])
    Print(L["CORE_HELP_SEARCH"])
    Print(L["CORE_HELP_LOOT_CHECK"])
    Print(L["CORE_HELP_LOOT_RECENT"])
    Print(L["CORE_HELP_LOOT_UI"])
    Print(L["CORE_HELP_LOOT_STATS"])
    Print(L["CORE_HELP_LOOT_EXPORT"])
    Print(L["CORE_HELP_LOOT_IMPORT"])
    Print(L["CORE_HELP_STOCK"])
    Print(L["CORE_HELP_MIN"])
    Print(L["CORE_HELP_MISSING"])
    Print(L["CORE_HELP_CHECK"])
    Print(L["CORE_HELP_STORAGE"])
    Print(L["CORE_HELP_COLLECT"])
    Print(L["CORE_HELP_REPORT"])
    Print(L["CORE_HELP_STYLE"])
    Print(L["CORE_HELP_HELPWINDOW"])
    Print(L["CORE_HELP_EXPORT"])
    Print(L["CORE_HELP_IMPORT"])
    Print(L["CORE_HELP_RESET"])
end

SLASH_GRINDKEEP1 = "/gkeep"
SlashCmdList["GRINDKEEP"] = function(msg)
    local args = {}
    for w in msg:gmatch("%S+") do table.insert(args, w) end
    local cmd = args[1] and args[1]:lower()
    -- Alles nach dem Befehl als ein Text: Charaktere koennen in WoW
    -- Forever Vor- UND Nachnamen haben ("Krutolo Zitterhand").
    local restText = msg:gsub("^%s*%S+%s*", ""):gsub("%s+$", "")

    if cmd == nil then
        if _G.GrindkeepUI then
            _G.GrindkeepUI.Toggle()
        else
            PrintHelp()
        end
    elseif cmd == "options" then
        if not (_G.GrindkeepOptions and _G.GrindkeepOptions.OpenToCategory()) then
            Print(L["CORE_OPTIONS_UNAVAILABLE"])
        end
    elseif cmd == "scan" then
        StartScan()
    elseif cmd == "stock" then
        if args[2] and args[2]:lower() == "scan" then
            StartInventoryScan()
        else
            PrintStock(args[2])
        end
    elseif cmd == "min" then
        -- Rohtext ab dem Befehl weitergeben: Itemlinks enthalten
        -- Leerzeichen und wuerden durch die Wort-Aufteilung zerrissen.
        HandleMinCommand((msg:gsub("^%s*[Mm][Ii][Nn]%s*", "")))
    elseif cmd == "missing" then
        PrintMissing()
    elseif cmd == "check" then
        PrintCheck()
    elseif cmd == "help" then
        if _G.GrindkeepHelpUI then
            _G.GrindkeepHelpUI.Show()
        else
            PrintHelp()
        end
    elseif cmd == "style" then
        if _G.GrindkeepStyle then
            local rest = {}
            for i = 2, #args do table.insert(rest, args[i]) end
            _G.GrindkeepStyle.HandleCommand(rest)
        end
    elseif cmd == "list" then
        PrintList(args[2])
    elseif cmd == "player" then
        PrintDetails(restText ~= "" and restText or nil)
    elseif cmd == "tx" then
        -- Optionaler Filter am Ende: gold | item | all
        local name, category = restText:match("^(.-)%s+(%a+)$")
        if category and (category == "gold" or category == "item" or category == "all") then
            PrintTransactions(name, category)
        else
            PrintTransactions(restText ~= "" and restText or nil)
        end
    elseif cmd == "alt" then
        -- /gkeep alt Twink = Main   (mit "=" auch fuer Namen mit Leerzeichen)
        -- /gkeep alt Twink Main     (Kurzform fuer einfache Namen)
        local twink, main = restText:match("^(.-)%s*=%s*(.-)$")
        if not twink and #args == 3 then twink, main = args[2], args[3] end
        if twink and main and twink ~= "" and main ~= "" and DB.SetAlt(twink, main) then
            local root = DB.GetMain(twink)
            Print(string.format(L["CORE_ALT_ASSIGNED"], twink, root))
            if _G.GrindkeepComm then _G.GrindkeepComm.BroadcastAltAssignment(twink, root) end
            if _G.GrindkeepUI then _G.GrindkeepUI.Refresh() end
        else
            Print(L["CORE_ALT_USAGE"])
        end
    elseif cmd == "namen" or cmd == "names" then
        -- Diagnose (seit 1.3.1): wie sieht Grindkeep Namen in WoW Forever?
        local info = _G.GrindkeepComm and _G.GrindkeepComm.NameInfo and _G.GrindkeepComm.NameInfo() or {}
        Print(string.format(L["CORE_NAMES_SELF"], tostring(info.unitName), tostring(info.fullName), tostring(info.realm)))
        Print(string.format(L["CORE_NAMES_RANK"], info.rankFound and tostring(info.rank) or L["CORE_NAMES_NOT_FOUND"],
            info.trusted and L["CORE_NAMES_YES"] or L["CORE_NAMES_NO"]))
        local shown = 0
        if IsInGuild and IsInGuild() and GetNumGuildMembers then
            for i = 1, math.min(GetNumGuildMembers() or 0, 3) do
                local full = GetGuildRosterInfo(i)
                if full then
                    Print(string.format(L["CORE_NAMES_ROSTER"], full, tostring(DB.NameKey(full))))
                    shown = shown + 1
                end
            end
        end
        local g = DB.GetGuildData()
        if g and g.transactions then
            local seen, n = {}, 0
            for i = #g.transactions, 1, -1 do
                local p = g.transactions[i].player
                if p and not seen[p] then
                    seen[p] = true
                    Print(string.format(L["CORE_NAMES_BANKLOG"], p, tostring(DB.NameKey(p))))
                    n = n + 1
                    if n >= 3 then break end
                end
            end
        end
        Print(string.format(L["CORE_NAMES_SENDER"], tostring(info.lastSender or "-"), tostring(info.lastSenderFull or "-")))
    elseif cmd == "unalt" then
        if restText ~= "" and DB.ClearAlt(restText) then
            Print(string.format(L["CORE_ALT_CLEARED"], restText))
            if _G.GrindkeepComm and _G.GrindkeepComm.BroadcastAltRemoval then
                _G.GrindkeepComm.BroadcastAltRemoval(restText)
            end
            if _G.GrindkeepUI then _G.GrindkeepUI.Refresh() end
        else
            Print(string.format(L["CORE_ALT_NOT_FOUND"], restText))
        end
    elseif cmd == "banktab" then
        if _G.GrindkeepUI and _G.GrindkeepUI.BankTabDiagnose then
            _G.GrindkeepUI.BankTabDiagnose()
        end
    elseif cmd == "lager" or cmd == "storage" then
        if _G.GrindkeepStorage then _G.GrindkeepStorage.HandleCommand(restText) end
    elseif cmd == "sammel" or cmd == "sammelliste" or cmd == "collect" then
        if _G.GrindkeepCollectUI then _G.GrindkeepCollectUI.Show() end
    elseif cmd == "bericht" or cmd == "report" then
        if _G.GrindkeepExportUI then
            local map = { sammel = "collect", sammelliste = "collect", collect = "collect", bestand = "stock", stock = "stock",
                vorgaenge = "tx", ["vorgänge"] = "tx", tx = "tx", bilanz = "balances", bilanzen = "balances", balances = "balances" }
            _G.GrindkeepExportUI.Show(map[(args[2] or ""):lower()])
        end
    elseif cmd == "search" then
        if _G.GrindkeepUI and _G.GrindkeepUI.ShowSearch then
            _G.GrindkeepUI.ShowSearch(restText)
        end
    elseif cmd == "loot" then
        if _G.GrindkeepLoot then
            local rest = {}
            for i = 3, #args do table.insert(rest, args[i]) end
            _G.GrindkeepLoot.HandleSlash(args[2], rest)
        else
            Print(L["LOOT_MODULE_NOT_LOADED"])
        end
    elseif cmd == "webseite" or cmd == "website" or cmd == "web" then
        -- Webseiten-Export (seit 1.4.0): /gkeep webseite [alles|<Tage>]
        if _G.GrindkeepWebExport then _G.GrindkeepWebExport.Show(args[2]) end
    elseif cmd == "export" then
        if _G.GrindkeepComm then _G.GrindkeepComm.Export() end
    elseif cmd == "import" then
        if _G.GrindkeepComm then
            if args[2] then
                -- Direkter Weg mit String als Argument: funktioniert nur
                -- zuverlaessig fuer kurze Strings, da die Chat-Eingabezeile
                -- selbst ein festes Zeichenlimit hat (siehe Comm.lua).
                _G.GrindkeepComm.Import(args[2])
            else
                -- Empfohlener Weg fuer laengere Exporte: eigenes,
                -- unbegrenztes Einfuege-Fenster.
                _G.GrindkeepComm.ShowImportDialog()
            end
        end
    elseif cmd == "reset" then
        if args[2] and args[2]:lower() == "confirm" then
            DB.ResetGuildData()
            Print(L["CORE_RESET_DONE"])
        else
            Print(L["CORE_RESET_CONFIRM"])
        end
    else
        PrintHelp()
    end
end

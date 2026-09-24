--[[
    Grindkeep - Database.lua

    Persistenz- und Datenmodell-Schicht. Kennt nichts von Events oder der
    Gildenbank-API selbst (das macht Core.lua) - hier geht es nur darum,
    WIE Transaktionen gespeichert, aggregiert und wieder abgefragt werden.

    Welche Log-Eintraege neu sind, entscheidet Core.lua (Abgleich mit den
    gespeicherten Daten, siehe dort). Diese Schicht speichert, rechnet
    Summen und beantwortet Abfragen fuer die Fenster.

    Schema von GrindkeepDB (SavedVariables):

    GrindkeepDB = {
        guilds = {
            ["<Gildenname>[-<Realm>]"] = {

                -- Rohdaten, chronologisch alt -> neu angehaengt.
                transactions = {
                    {
                        id,                          -- fortlaufende interne ID (kein Content-Hash!)
                        ts, player,
                        kind = "gold" | "item",
                        action = "deposit" | "withdraw" | "move" | "repair" | ...,
                        tab, tabName,
                        amount,                       -- nur kind == "gold" (Kupfer)
                        itemID, itemLink, count,       -- nur kind == "item"
                        itemName, itemQuality, itemType, -- item, evtl. erst spaeter befuellt
                    },
                    ...
                },

                nextSeq = 0,               -- Zaehler fuer die naechste transactions-ID
                transactionsById = {},     -- [id] = Index in transactions, fuer O(1)-Zugriff

                -- Vorberechnete Summen je Charakter.
                playerSummary = {
                    ["<Name>"] = {
                        goldDeposited = 0, goldWithdrawn = 0,
                        itemDeposits = 0, itemWithdrawals = 0,
                        byCategory = { ["<itemType|?>"] = { deposits = 0, withdrawals = 0 } },
                        lastActivity = 0,
                    },
                },

                -- Zuletzt bekannte Fachnamen: [tabIndex] = "Name"
                tabNames = {},

                -- Was beim letzten bestaetigten Scan im Log eines Fachs
                -- bzw. im Geld-Log sichtbar war (chronologisch), mit den
                -- IDs der zugehoerigen gespeicherten Eintraege - Grundlage
                -- fuer den Abgleich in Core.lua.
                logBaseline = { ["item:<tab>" | "gold"] = { { key, ts, id }, ... } },

                -- Manuelle Main-/Twink-Zuordnung: ["Twink"] = "Hauptcharakter"
                -- (immer direkt auf den Hauptcharakter, nie auf einen Twink)
                alts = {},

                -- Items, die beim Scan noch unbekannt waren: [itemID] = { id1, id2, ... },
                -- werden nachtraeglich ueber GET_ITEM_INFO_RECEIVED (Core.lua) aufgefuellt.
                pendingItems = {},

                -- Raid-Loot (siehe Loot.lua): wer hat welches Item wann bekommen.
                -- Chronologisch alt -> neu angehaengt, genau wie transactions oben -
                -- gleiches Muster, eigene Tabelle, da inhaltlich unabhaengig von der
                -- Gildenbank (Loot kommt aus CHAT_MSG_LOOT bzw. Gilden-Broadcast,
                -- nicht aus der Gildenbank-API).
                loot = {
                    {
                        id,                          -- fortlaufende interne ID
                        ts, recipient,
                        itemID, itemLink, itemName, itemQuality,
                        count,
                        raidName,                     -- Zonenname zum Zeitpunkt der Vergabe (best effort)
                        lootMethod,                   -- "master" | "group" | "personalloot" | ... (best effort)
                        reportedBy,                   -- nur gesetzt, wenn per Gilden-Broadcast uebernommen
                    },
                    ...
                },
                lootNextSeq = 0,
                lootById = {},
            },
        },
    }
]]

-- WICHTIG: SavedVariables stehen beim Ausfuehren dieser Datei noch NICHT
-- zur Verfuegung - WoW laedt sie erst, nachdem alle Dateien des Addons
-- gelaufen sind, und meldet das dann mit ADDON_LOADED. Alles, was
-- gespeicherte Daten liest (Migration, Aufraeumen, Einstellungen fuer
-- Fenster/Minimap), passiert deshalb in Database.OnLoad() weiter unten,
-- das Core.lua beim ADDON_LOADED dieses Addons aufruft. Der Platzhalter
-- hier verhindert nur Fehler, falls vorher schon etwas darauf zugreift.
GrindkeepDB = GrindkeepDB or {}

local Database = {}
_G.GrindkeepDatabase = Database

-- Einheitliche Uhr fuer alle gespeicherten Zeitpunkte: die Serverzeit.
-- Die Uhr des eigenen PCs kann falsch gehen oder springen (Zeitumstellung,
-- falsch gestellte Uhr) - dann wuerden Vorgaenge beim Abgleich nicht mehr
-- wiedererkannt oder Zeitangaben verschiedener Spieler passten nicht
-- zusammen.
function Database.Now()
    if GetServerTime then
        local ok, t = pcall(GetServerTime)
        if ok and type(t) == "number" and t > 0 then return t end
    end
    return time()
end

-- ============================================================
-- Gilden-Schluessel
-- ============================================================
-- GetGuildInfo liefert den Realm NUR, wenn die Gilde auf einem anderen
-- Realm als der eigene Charakter liegt. Fuer die eigene Heimat-Gilde
-- kommt nil zurueck - ohne Rueckfall wuerden zwei gleichnamige Gilden auf
-- verschiedenen Realms denselben Datentopf teilen. Deshalb faellt der
-- Schluessel auf den eigenen Realm zurueck. Liefert ein Client gar keinen
-- Realm (z.B. ein realmloses Spiel), bleibt es beim reinen Gildennamen.
local function NormalizeRealm(realm)
    if type(realm) ~= "string" then return nil end
    realm = realm:gsub("[%s%-]", "")
    if realm == "" then return nil end
    return realm
end

-- Rueckgabe: neuer Schluessel, Liste frueherer Schluessel derselben Gilde
local function GuildKeyParts()
    local name, _, _, rawRealm = GetGuildInfo("player")
    if not name then return nil end
    -- Realm ohne Leerzeichen/Bindestriche: GetGuildInfo liefert "Die Aldor",
    -- GetNormalizedRealmName "DieAldor" - beides soll derselbe Schluessel sein.
    local realm = NormalizeRealm(rawRealm) or NormalizeRealm(GetNormalizedRealmName and GetNormalizedRealmName())
    local key = realm and (name .. "-" .. realm) or name
    local legacy = { name }
    if type(rawRealm) == "string" and rawRealm ~= "" then
        table.insert(legacy, name .. "-" .. rawRealm)
    end
    return key, legacy
end

local function GuildKey()
    return (GuildKeyParts())
end
Database.GuildKey = GuildKey

local function EnsureGuildData(key)
    GrindkeepDB.guilds = GrindkeepDB.guilds or {}
    local g = GrindkeepDB.guilds[key]
    if not g then
        g = {
            transactions = {},
            nextSeq = 0,
            transactionsById = {},
            playerSummary = {},
            alts = {},
            tabNames = {},
            pendingItems = {},
            loot = {},
            lootNextSeq = 0,
            lootById = {},
            inventory = { items = {}, scannedAt = nil, tabs = {} },
            minimums = {},
        }
        GrindkeepDB.guilds[key] = g
    end
    -- Absicherung fuer Daten aus einer aelteren Version dieses Addons,
    -- die einzelne Felder noch nicht kannte (Migration light).
    g.transactions = g.transactions or {}
    g.nextSeq = g.nextSeq or 0
    g.transactionsById = g.transactionsById or {}
    g.playerSummary = g.playerSummary or {}
    g.tabNames = g.tabNames or {}
    g.logBaseline = g.logBaseline or {}
    g.alts = g.alts or {}
    g.pendingItems = g.pendingItems or {}
    g.loot = g.loot or {}
    g.lootNextSeq = g.lootNextSeq or 0
    g.lootById = g.lootById or {}
    -- Bestand (Inhalt der Faecher) und Mindestbestaende - seit v0.8.
    -- Bewusst getrennt von den Transaktionen: das Log sagt, wer etwas
    -- bewegt hat, der Bestand sagt, was JETZT drin liegt. Beides ist
    -- unabhaengig voneinander nutzbar.
    g.inventory = g.inventory or { items = {}, scannedAt = nil, tabs = {} }
    g.inventory.items = g.inventory.items or {}
    g.inventory.tabs = g.inventory.tabs or {}
    g.minimums = g.minimums or {}
    return g
end
Database.EnsureGuildData = EnsureGuildData

-- Daten eines alten Schluessels in den neuen uebernehmen. Vorgaenge, die
-- es in beiden gibt, werden nur einmal uebernommen (gleicher Abgleich wie
-- beim Import, siehe Core.lua).
local MergeGuildData -- unten definiert (braucht RebuildSummaries)

local function GetGuildData()
    local key, legacyKeys = GuildKeyParts()
    if not key then return nil end
    -- Uebernahme aus Versionen bis 0.9.x, die den Realm fuer die eigene
    -- Gilde weggelassen bzw. anders geschrieben haben.
    if GrindkeepDB.guilds then
        for _, legacyKey in ipairs(legacyKeys) do
            local old = legacyKey ~= key and GrindkeepDB.guilds[legacyKey]
            if old then
                if GrindkeepDB.guilds[key] == nil then
                    GrindkeepDB.guilds[key] = old
                else
                    MergeGuildData(EnsureGuildData(key), EnsureGuildData(legacyKey))
                end
                GrindkeepDB.guilds[legacyKey] = nil
            end
        end
    end
    return EnsureGuildData(key)
end
Database.GetGuildData = GetGuildData

-- ============================================================
-- Spieler-Summary
-- ============================================================
local function EnsurePlayerSummary(g, name)
    local s = g.playerSummary[name]
    if not s then
        s = {
            goldDeposited = 0,
            goldWithdrawn = 0,
            itemDeposits = 0,
            itemWithdrawals = 0,
            byCategory = {},
            lastActivity = 0,
            txCount = 0,
        }
        g.playerSummary[name] = s
    end
    return s
end
Database.EnsurePlayerSummary = EnsurePlayerSummary

-- Unbekannte Kategorie wird neutral als "?" gespeichert und erst bei der
-- Anzeige uebersetzt - sonst stuende in den Daten englischer Spieler
-- dauerhaft das deutsche Wort "Unbekannt".
Database.UNKNOWN_CATEGORY = "?"

local function BumpCategory(summary, category, action, count)
    category = category or Database.UNKNOWN_CATEGORY
    local cat = summary.byCategory[category]
    if not cat then
        cat = { deposits = 0, withdrawals = 0 }
        summary.byCategory[category] = cat
    end
    if action == "deposit" then
        cat.deposits = cat.deposits + count
    elseif action == "withdraw" then
        cat.withdrawals = cat.withdrawals + count
    end
end

-- ============================================================
-- Main-/Twink-Verwaltung (manuell)
-- ============================================================
-- Die Zuordnung ist immer genau eine Ebene tief: jeder Twink zeigt direkt
-- auf seinen Hauptcharakter, nie auf einen anderen Twink. Ketten (A -> B,
-- B -> C) oder Schleifen (A -> B, B -> A) wuerden sonst Gold doppelt
-- zaehlen oder Eintraege verschwinden lassen. Das gilt auch fuer
-- Zuordnungen, die per Gilden-Abgleich hereinkommen (Comm.lua ruft
-- ebenfalls SetAlt auf).
local function ResolveMain(alts, name)
    local seen = {}
    local current = name
    while alts[current] and not seen[current] do
        seen[current] = true
        current = alts[current]
    end
    return current
end

function Database.SetAlt(twinkName, mainName)
    local g = GetGuildData()
    if not g or type(twinkName) ~= "string" or type(mainName) ~= "string" then return false end
    if twinkName == "" or mainName == "" or twinkName == mainName then return false end

    local root = ResolveMain(g.alts, mainName)
    if root == twinkName then
        -- Der Hauptcharakter haengt selbst schon an diesem Twink - die
        -- Zuordnung wuerde eine Schleife bilden.
        return false
    end

    g.alts[twinkName] = root
    -- War der neue Twink bisher selbst Hauptcharakter, ziehen seine
    -- Twinks mit zum neuen Hauptcharakter um.
    for alt, main in pairs(g.alts) do
        if main == twinkName then g.alts[alt] = root end
    end
    -- Selbstverweise koennen aus aelteren Versionen stammen - aufraeumen.
    for alt, main in pairs(g.alts) do
        if alt == main then g.alts[alt] = nil end
    end
    return true
end

function Database.ClearAlt(twinkName)
    local g = GetGuildData()
    if not g or not twinkName or not g.alts[twinkName] then return false end
    g.alts[twinkName] = nil
    return true
end

function Database.GetMain(name)
    local g = GetGuildData()
    if not g then return name end
    return ResolveMain(g.alts, name)
end

-- Repariert Zuordnungen aus Versionen bis 0.9.x, in denen Ketten und
-- Schleifen noch moeglich waren: danach zeigt jeder Twink direkt auf
-- seinen Hauptcharakter.
local function NormalizeAlts(g)
    local fixed = {}
    for alt in pairs(g.alts) do
        local root = ResolveMain(g.alts, alt)
        if root ~= alt then fixed[alt] = root end
    end
    g.alts = fixed
end
Database.NormalizeAlts = NormalizeAlts

-- ============================================================
-- Transaktion speichern
-- ============================================================
-- record: { ts, player, kind, action, tab, tabName, amount,
--           itemID, itemLink, count, itemName, itemQuality, itemType }
-- Core.lua hat zu diesem Zeitpunkt bereits entschieden, dass dieser
-- Eintrag neu ist (siehe dortige ComputeNewCount-Logik) - hier wird
-- ungeprueft gespeichert und eine fortlaufende interne ID vergeben.
-- Rueckgabe: die vergebene ID.
-- Rechnet einen einzelnen Eintrag in eine Summen-Tabelle ein. Wird fuer
-- die laufende Gesamtbilanz (playerSummary), fuer den kompletten
-- Neuaufbau (RebuildSummaries) und fuer die Zeitraum-Uebersicht benutzt,
-- damit alle drei garantiert gleich rechnen.
local function NewSummary()
    return {
        goldDeposited = 0, goldWithdrawn = 0,
        itemDeposits = 0, itemWithdrawals = 0,
        byCategory = {}, lastActivity = 0, txCount = 0,
    }
end

local function ApplyToSummary(summaryMap, record)
    local name = record.player or "?"
    local summary = summaryMap[name]
    if not summary then
        summary = NewSummary()
        summaryMap[name] = summary
    end
    if record.ts and record.ts > summary.lastActivity then
        summary.lastActivity = record.ts
    end
    summary.txCount = (summary.txCount or 0) + 1

    if record.kind == "gold" then
        if record.action == "deposit" then
            summary.goldDeposited = summary.goldDeposited + (record.amount or 0)
        elseif record.action == "withdraw" or record.action == "withdrawal" then
            summary.goldWithdrawn = summary.goldWithdrawn + (record.amount or 0)
        end
        -- "repair" wird mitgeloggt, aber bewusst nicht als Ein-/Auszahlung gewertet.
    elseif record.kind == "item" then
        if record.action == "deposit" then
            summary.itemDeposits = summary.itemDeposits + (record.count or 0)
            BumpCategory(summary, record.itemType, "deposit", record.count or 0)
        elseif record.action == "withdraw" then
            summary.itemWithdrawals = summary.itemWithdrawals + (record.count or 0)
            BumpCategory(summary, record.itemType, "withdraw", record.count or 0)
        end
        -- "move" (Tab-zu-Tab) wird gespeichert, aber nicht in die Bilanz gerechnet.
    end
end

-- Baut Indizes und Gesamtsummen einer Gilde komplett aus den Rohdaten
-- neu auf. Noetig nach dem Aufraeumen alter Eintraege und beim Umstieg
-- von aelteren Versionen (andere Kategorie-Schluessel).
local function RebuildSummaries(g)
    g.playerSummary = {}
    g.transactionsById = {}
    for i, record in ipairs(g.transactions) do
        if record.id then g.transactionsById[record.id] = i end
        ApplyToSummary(g.playerSummary, record)
    end
    g.lootById = {}
    for i, entry in ipairs(g.loot) do
        if entry.id then g.lootById[entry.id] = i end
    end
end
Database.RebuildSummaries = RebuildSummaries

MergeGuildData = function(dst, src)
    local M = _G.GrindkeepMatcher
    local function mergeList(dstList, srcList, keyFn, tolFn)
        local visible = {}
        for i, rec in ipairs(srcList) do visible[i] = { key = (keyFn or M.RecordKey)(rec), ts = rec.ts or 0, rec = rec } end
        table.sort(visible, function(a, b) return a.ts > b.ts end)
        local newIdx = M and M.FindNewEntries(visible, dstList, Database.Now(), keyFn, tolFn) or {}
        for n = #newIdx, 1, -1 do table.insert(dstList, visible[newIdx[n]].rec) end
    end
    if M then
        mergeList(dst.transactions, src.transactions)
        mergeList(dst.loot, src.loot, M.LootKey, M.LootTolerance)
        -- IDs neu vergeben, damit sie eindeutig bleiben
        local seq = 0
        for _, rec in ipairs(dst.transactions) do seq = seq + 1; rec.id = seq end
        dst.nextSeq = seq
        seq = 0
        for _, e in ipairs(dst.loot) do seq = seq + 1; e.id = seq end
        dst.lootNextSeq = seq
        dst.pendingItems = {}
    end
    for alt, main in pairs(src.alts or {}) do
        if dst.alts[alt] == nil then dst.alts[alt] = main end
    end
    NormalizeAlts(dst)
    for itemID, min in pairs(src.minimums or {}) do
        if dst.minimums[itemID] == nil then dst.minimums[itemID] = min end
    end
    RebuildSummaries(dst)
end


-- record: { ts, player, kind, action, tab, tabName, amount,
--           itemID, itemLink, count, itemName, itemQuality, itemType }
-- Core.lua hat zu diesem Zeitpunkt bereits entschieden, dass dieser
-- Eintrag neu ist - hier wird gespeichert und eine fortlaufende interne
-- ID vergeben. Rueckgabe: die vergebene ID.
function Database.AddTransaction(record)
    local g = GetGuildData()
    if not g or type(record) ~= "table" then return nil end
    if type(record.player) ~= "string" or record.player == "" then record.player = "?" end

    g.nextSeq = g.nextSeq + 1
    record.id = g.nextSeq
    table.insert(g.transactions, record)
    g.transactionsById[record.id] = #g.transactions

    ApplyToSummary(g.playerSummary, record)
    return record.id
end

-- Alle gespeicherten Eintraege eines Scan-Ziels (ein Fach oder das
-- Geld-Log) ab einem Zeitpunkt - Grundlage fuer den Abgleich in Core.lua.
function Database.GetTransactionsForTarget(kind, tab, sinceTs)
    local g = GetGuildData()
    if not g then return {} end
    local out = {}
    for _, tx in ipairs(g.transactions) do
        if tx.kind == kind and (kind ~= "item" or tx.tab == tab)
            and (tx.ts or 0) >= (sinceTs or 0) then
            table.insert(out, tx)
        end
    end
    return out
end

-- ============================================================
-- Nachtraegliche Item-Anreicherung (async Item-Cache, siehe Core.lua)
-- ============================================================
function Database.QueueItemLookup(itemID, id)
    local g = GetGuildData()
    if not g or not itemID or not id then return end
    g.pendingItems[itemID] = g.pendingItems[itemID] or {}
    table.insert(g.pendingItems[itemID], id)
end

function Database.EnrichItem(itemID, itemName, itemLink, itemQuality, itemType)
    local g = GetGuildData()
    if not g then return end
    local ids = g.pendingItems[itemID]
    if not ids then return end

    for _, id in ipairs(ids) do
        local idx = g.transactionsById[id]
        local record = idx and g.transactions[idx]
        if record and not record.itemName then
            record.itemName = itemName
            record.itemLink = record.itemLink or itemLink
            record.itemQuality = itemQuality
            record.itemType = itemType

            if record.action == "deposit" or record.action == "withdraw" then
                local summary = g.playerSummary[record.player]
                if summary then
                    local unknown = summary.byCategory[Database.UNKNOWN_CATEGORY]
                    if unknown then
                        if record.action == "deposit" then
                            unknown.deposits = math.max(0, unknown.deposits - (record.count or 0))
                        else
                            unknown.withdrawals = math.max(0, unknown.withdrawals - (record.count or 0))
                        end
                    end
                    BumpCategory(summary, itemType, record.action, record.count or 0)
                end
            end
        end
    end

    g.pendingItems[itemID] = nil
end

-- ============================================================
-- Getter-API fuers UI
-- ============================================================
-- Summen je Charakter fuer einen Zeitraum (sinceTs = nil: alles). Fuer
-- "alles" gibt es die laufend gepflegte Gesamtbilanz, fuer einen
-- Zeitraum wird aus den Rohdaten gerechnet - mit derselben Logik.
local function ComputeSummaries(g, sinceTs)
    if not sinceTs then return g.playerSummary end
    local map = {}
    for _, record in ipairs(g.transactions) do
        if (record.ts or 0) >= sinceTs then
            ApplyToSummary(map, record)
        end
    end
    return map
end
Database.ComputeSummaries = ComputeSummaries

local function AggregatedSummary(g, name, summaryMap)
    summaryMap = summaryMap or g.playerSummary
    local main = ResolveMain(g.alts, name)
    local members = { main }
    for twink, m in pairs(g.alts) do
        if m == main and twink ~= main then table.insert(members, twink) end
    end

    local agg = NewSummary()
    for _, member in ipairs(members) do
        local s = summaryMap[member]
        if s then
            agg.goldDeposited = agg.goldDeposited + s.goldDeposited
            agg.goldWithdrawn = agg.goldWithdrawn + s.goldWithdrawn
            agg.itemDeposits = agg.itemDeposits + s.itemDeposits
            agg.itemWithdrawals = agg.itemWithdrawals + s.itemWithdrawals
            if s.lastActivity > agg.lastActivity then agg.lastActivity = s.lastActivity end
            agg.txCount = agg.txCount + (s.txCount or 0)
            for cat, v in pairs(s.byCategory) do
                local c = agg.byCategory[cat] or { deposits = 0, withdrawals = 0 }
                c.deposits = c.deposits + v.deposits
                c.withdrawals = c.withdrawals + v.withdrawals
                agg.byCategory[cat] = c
            end
        end
    end
    return agg
end
Database.AggregatedSummary = AggregatedSummary

-- Grindkeep:GetPlayerList(sortBy, sinceTs)
-- sortBy: "net" (Standard), "deposits", "activity", "name"
-- sinceTs: nur Vorgaenge ab diesem Zeitpunkt (nil = gesamter Verlauf)
function Database.GetPlayerList(sortBy, sinceTs)
    local g = GetGuildData()
    if not g then return {} end
    sortBy = sortBy or "net"
    local summaryMap = ComputeSummaries(g, sinceTs)

    local roots = {}
    for name in pairs(summaryMap) do
        roots[ResolveMain(g.alts, name)] = true
    end
    if not sinceTs then
        -- Gesamtansicht: Hauptcharaktere auch dann zeigen, wenn nur ihre
        -- Twinks etwas in der Bank bewegt haben.
        for _, main in pairs(g.alts) do roots[main] = true end
    end

    local list = {}
    for name in pairs(roots) do
        local summary = AggregatedSummary(g, name, summaryMap)
        table.insert(list, { name = name, net = summary.goldDeposited - summary.goldWithdrawn, summary = summary })
    end

    table.sort(list, function(a, b)
        if sortBy == "deposits" then
            if a.summary.goldDeposited ~= b.summary.goldDeposited then
                return a.summary.goldDeposited > b.summary.goldDeposited
            end
        elseif sortBy == "activity" then
            if a.summary.lastActivity ~= b.summary.lastActivity then
                return a.summary.lastActivity > b.summary.lastActivity
            end
        elseif sortBy ~= "name" then
            if a.net ~= b.net then return a.net > b.net end
        end
        return a.name < b.name
    end)

    return list
end

-- Grindkeep:GetPlayerDetails(playerName, sinceTs)
function Database.GetPlayerDetails(playerName, sinceTs)
    local g = GetGuildData()
    if not g or not playerName then return nil end
    local summaryMap = ComputeSummaries(g, sinceTs)

    local twinks = {}
    for twink, main in pairs(g.alts) do
        if main == playerName then table.insert(twinks, twink) end
    end
    table.sort(twinks)

    return {
        name = playerName,
        isTwinkOf = g.alts[playerName],
        twinks = twinks,
        own = summaryMap[playerName],
        aggregated = AggregatedSummary(g, playerName, summaryMap),
    }
end

-- Summen ueber die ganze Gilde fuer die Uebersicht (sinceTs = nil: alles).
function Database.GetGuildTotals(sinceTs)
    local totals = { goldIn = 0, goldOut = 0, itemsIn = 0, itemsOut = 0, txCount = 0, players = 0, lastActivity = 0 }
    local g = GetGuildData()
    if not g then return totals end
    for _, s in pairs(ComputeSummaries(g, sinceTs)) do
        totals.goldIn = totals.goldIn + (s.goldDeposited or 0)
        totals.goldOut = totals.goldOut + (s.goldWithdrawn or 0)
        totals.itemsIn = totals.itemsIn + (s.itemDeposits or 0)
        totals.itemsOut = totals.itemsOut + (s.itemWithdrawals or 0)
        totals.txCount = totals.txCount + (s.txCount or 0)
        if (s.txCount or 0) > 0 then totals.players = totals.players + 1 end
        if (s.lastActivity or 0) > totals.lastActivity then totals.lastActivity = s.lastActivity end
    end
    return totals
end

-- Anzahl aller gespeicherten Vorgaenge (unabhaengig vom Zeitraum)
function Database.CountTransactions()
    local g = GetGuildData()
    return g and #g.transactions or 0
end

-- Wann wurde das Bank-Log zuletzt vollstaendig gelesen, und wie viele
-- Faecher waren dabei einsehbar? Fuer die Statuszeile und den Hinweis,
-- warum noch nichts angezeigt wird.
function Database.SetLastLogScan(itemTabs)
    local g = GetGuildData()
    if not g then return end
    g.lastLogScan = { at = Database.Now(), tabs = itemTabs or 0 }
end

function Database.GetLastLogScan()
    local g = GetGuildData()
    return g and g.lastLogScan or nil
end

-- Suche ueber alle Vorgaenge (neueste zuerst).
-- filter = {
--   text   = Teilstring in Spieler-, Item- oder Fachname (ohne Gross/klein),
--   itemID = exakte Item-ID (z.B. aus einem eingefuegten Itemlink),
--   kind   = "gold" | "item" | nil,
--   action = "deposit" | "withdraw" | "move" | "repair" | ... | nil,
--   player = Charakter; schliesst dessen Twinks mit ein,
--   sinceTs = nur ab diesem Zeitpunkt,
--   limit  = hoechstens so viele Treffer (Standard 500),
-- }
function Database.SearchTransactions(filter)
    local g = GetGuildData()
    if not g then return {} end
    filter = filter or {}
    local text = filter.text and filter.text ~= "" and filter.text:lower() or nil
    local limit = filter.limit or 500

    local players
    if filter.player then
        players = {}
        local main = ResolveMain(g.alts, filter.player)
        players[main] = true
        for twink, m in pairs(g.alts) do
            if m == main then players[twink] = true end
        end
    end

    local out = {}
    -- Rueckwaerts laufen: die Daten sind grob chronologisch angehaengt,
    -- so kommen die neuesten Treffer zuerst und das Limit greift sinnvoll.
    for i = #g.transactions, 1, -1 do
        local tx = g.transactions[i]
        local ok = true
        if filter.kind and tx.kind ~= filter.kind then ok = false end
        if ok and filter.action then
            local action = tx.action == "withdrawal" and "withdraw" or tx.action
            if action ~= filter.action then ok = false end
        end
        if ok and filter.sinceTs and (tx.ts or 0) < filter.sinceTs then ok = false end
        if ok and players and not players[tx.player or "?"] then ok = false end
        if ok and filter.itemID and tx.itemID ~= filter.itemID then ok = false end
        if ok and text then
            local hay = ((tx.player or "") .. "\1" .. (tx.itemName or "") .. "\1" .. (tx.tabName or "")):lower()
            if not hay:find(text, 1, true) then ok = false end
        end
        if ok then
            table.insert(out, tx)
            if #out >= limit then break end
        end
    end

    table.sort(out, function(a, b)
        if (a.ts or 0) ~= (b.ts or 0) then return (a.ts or 0) > (b.ts or 0) end
        return (a.id or 0) > (b.id or 0)
    end)
    return out
end

-- Grindkeep:GetPlayerTransactions(playerName, categoryFilter, timeRange)
function Database.GetPlayerTransactions(playerName, categoryFilter, timeRange)
    local g = GetGuildData()
    if not g or not playerName then return {} end

    local fromTs, toTs
    if type(timeRange) == "number" then
        fromTs = Database.Now() - timeRange
    elseif type(timeRange) == "table" then
        fromTs = timeRange.from
        toTs = timeRange.to
    end

    local out = {}
    for _, tx in ipairs(g.transactions) do
        if tx.player == playerName then
            local matchesCategory =
                (not categoryFilter or categoryFilter == "all")
                or (categoryFilter == "gold" and tx.kind == "gold")
                or (categoryFilter == "item" and tx.kind == "item")
                or (tx.itemType == categoryFilter)
            local matchesTime =
                (not fromTs or (tx.ts or 0) >= fromTs) and
                (not toTs or (tx.ts or 0) <= toTs)

            if matchesCategory and matchesTime then
                table.insert(out, tx)
            end
        end
    end

    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end

-- ============================================================
-- Loot-Tracking (Raid-Beute: wer hat welches Item bekommen)
-- ============================================================
-- record: { ts, itemID, itemLink, itemName, itemQuality, count,
--           recipient, raidName, lootMethod, reportedBy }
-- Wie bei AddTransaction: der Aufrufer (Loot.lua) hat Dedup bereits
-- ueber einen kurzlebigen Fingerprint-Cache entschieden, dass dieser
-- Eintrag neu ist - hier wird ungeprueft gespeichert und eine
-- fortlaufende interne ID vergeben.
function Database.AddLoot(record)
    local g = GetGuildData()
    if not g or type(record) ~= "table" then return nil end

    g.lootNextSeq = g.lootNextSeq + 1
    record.id = g.lootNextSeq
    table.insert(g.loot, record)
    g.lootById[record.id] = #g.loot
    return record.id
end

-- Grindkeep:GetLootForItem(itemID, itemLinkFallback) - alle bekannten
-- Vergaben eines Items, neueste zuerst. itemLinkFallback greift nur,
-- wenn itemID nicht ermittelt werden konnte (sehr seltene, dem Client
-- unbekannte Items).
function Database.GetLootForItem(itemID, itemLinkFallback)
    local g = GetGuildData()
    if not g then return {} end

    local out = {}
    for _, entry in ipairs(g.loot) do
        local matches
        if itemID and entry.itemID then
            matches = entry.itemID == itemID
        else
            matches = itemLinkFallback ~= nil and entry.itemLink == itemLinkFallback
        end
        if matches then table.insert(out, entry) end
    end
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end

-- Grindkeep:SearchLoot(query) - einfache, case-insensitive Teilstring-
-- Suche ueber Item- und Empfaengername (fuer /gkeep loot check und das
-- Such-Fenster in Loot.lua).
function Database.SearchLoot(query)
    local g = GetGuildData()
    if not g or not query or query == "" then return {} end
    query = query:lower()

    local out = {}
    for _, entry in ipairs(g.loot) do
        local name = (entry.itemName or (entry.itemLink and entry.itemLink:match("%[(.-)%]")) or ""):lower()
        local recipient = (entry.recipient or ""):lower()
        if name:find(query, 1, true) or recipient:find(query, 1, true) then
            table.insert(out, entry)
        end
    end
    table.sort(out, function(a, b) return (a.ts or 0) > (b.ts or 0) end)
    return out
end

-- Grindkeep:GetRecentLoot(limit) - die letzten `limit` Eintraege,
-- neueste zuerst (Standardansicht, wenn noch keine Suche eingegeben ist).
function Database.GetRecentLoot(limit)
    local g = GetGuildData()
    if not g then return {} end
    limit = limit or 50

    local out = {}
    for i = #g.loot, 1, -1 do
        table.insert(out, g.loot[i])
        if #out >= limit then break end
    end
    return out
end

-- Grindkeep:GetLootPlayerStats(sortBy) - aggregiert die komplette Loot-
-- Historie je Empfaenger (Gesamtstueckzahl, Anzahl Vergabe-Ereignisse,
-- letzte Aktivitaet). Fuer die Statistik-Ansicht im Loot-Fenster
-- (Loot.lua) - beantwortet "wer hat zuletzt/insgesamt am meisten
-- bekommen", was bei Verteilungsentscheidungen (Loot-Rat/Prio-Liste)
-- hilft, ohne die komplette Rohliste durchscrollen zu muessen.
-- sortBy: "count" (Standard, Gesamtstueckzahl), "entries" (Anzahl
-- Vergaben), "activity" (letzte Vergabe), "name".
function Database.GetLootPlayerStats(sortBy)
    local g = GetGuildData()
    if not g then return {} end
    sortBy = sortBy or "count"

    local stats = {}
    for _, entry in ipairs(g.loot) do
        local name = entry.recipient or "?"
        local s = stats[name]
        if not s then
            s = { name = name, totalCount = 0, entries = 0, lastTs = 0 }
            stats[name] = s
        end
        s.totalCount = s.totalCount + (entry.count or 1)
        s.entries = s.entries + 1
        if (entry.ts or 0) > s.lastTs then s.lastTs = entry.ts or 0 end
    end

    local list = {}
    for _, s in pairs(stats) do table.insert(list, s) end

    table.sort(list, function(a, b)
        if sortBy == "entries" then
            return a.entries > b.entries
        elseif sortBy == "name" then
            return a.name < b.name
        elseif sortBy == "activity" then
            return a.lastTs > b.lastTs
        else
            return a.totalCount > b.totalCount
        end
    end)

    return list
end

-- ============================================================
-- Bestand (was liegt JETZT in den Faechern) - seit v0.8
--
-- Anders als die Transaktionen ist der Bestand kein fortgeschriebenes
-- Protokoll, sondern immer eine vollstaendige Momentaufnahme: beim Scan
-- wird der alte Stand komplett ersetzt. Das ist Absicht - ein Item, das
-- nicht mehr in der Bank liegt, soll auch nicht mehr im Bestand stehen,
-- und ein Zusammenrechnen alter und neuer Staende wuerde nur falsche
-- Zahlen erzeugen.
-- ============================================================
function Database.SetInventorySnapshot(items, tabsInfo)
    local g = GetGuildData()
    if not g then return false end

    local fresh = {}
    for itemID, entry in pairs(items or {}) do
        fresh[itemID] = {
            itemID = itemID,
            count = entry.count or 0,
            itemName = entry.itemName,
            itemLink = entry.itemLink,
            itemQuality = entry.itemQuality,
            tabs = entry.tabs, -- in welchen Faechern liegt es (Anzeige)
        }
    end

    g.inventory.items = fresh
    g.inventory.tabs = tabsInfo or {}
    g.inventory.scannedAt = Database.Now()
    return true
end

function Database.GetInventory()
    local g = GetGuildData()
    if not g then return nil end
    return g.inventory
end

function Database.GetInventoryCount(itemID)
    local g = GetGuildData()
    if not g or not itemID then return 0 end
    local entry = g.inventory.items[itemID]
    return entry and entry.count or 0
end

-- Sortierte Liste fuer die Anzeige. sortBy: "count" (Standard) | "name"
function Database.GetInventoryList(sortBy)
    local g = GetGuildData()
    if not g then return {} end

    local list = {}
    for _, entry in pairs(g.inventory.items) do
        table.insert(list, entry)
    end

    table.sort(list, function(a, b)
        if sortBy == "name" then
            return (a.itemName or "") < (b.itemName or "")
        end
        if a.count == b.count then
            return (a.itemName or "") < (b.itemName or "")
        end
        return a.count > b.count
    end)

    return list
end

-- ============================================================
-- Mindestbestaende und Fehlliste - seit v0.8
--
-- Pro Item wird eine Wunschmenge hinterlegt; die Fehlliste rechnet
-- daraus aus, was nachgelegt werden muss. Gespeichert wird zusaetzlich
-- der Itemname, damit die Liste auch dann lesbar bleibt, wenn der
-- Client das Item gerade nicht aufloesen kann.
-- ============================================================
function Database.SetMinimum(itemID, count, itemName, itemLink)
    local g = GetGuildData()
    if not g or not itemID then return false end
    count = tonumber(count)
    if not count or count < 0 then return false end

    if count == 0 then
        g.minimums[itemID] = nil
        return true
    end

    g.minimums[itemID] = {
        itemID = itemID,
        count = math.floor(count),
        itemName = itemName or (g.minimums[itemID] and g.minimums[itemID].itemName),
        itemLink = itemLink or (g.minimums[itemID] and g.minimums[itemID].itemLink),
    }
    return true
end

function Database.RemoveMinimum(itemID)
    local g = GetGuildData()
    if not g or not itemID then return false end
    if not g.minimums[itemID] then return false end
    g.minimums[itemID] = nil
    return true
end

function Database.GetMinimums()
    local g = GetGuildData()
    if not g then return {} end
    return g.minimums
end

-- Liefert je hinterlegtem Mindestbestand: Soll, Ist und Fehlmenge.
-- onlyMissing = true blendet alles aus, was bereits ausreichend da ist.
function Database.GetStockList(onlyMissing)
    local g = GetGuildData()
    if not g then return {} end

    local list = {}
    for itemID, min in pairs(g.minimums) do
        -- Gildenbank UND Lager-Twinks zaehlen (seit 1.3): ohne eigene Bank
        -- lagern viele Gilden bei Twinks, und auch danach liegt oft etwas dort.
        local haveBank = Database.GetInventoryCount(itemID)
        local haveStorage = Database.GetStorageCount and Database.GetStorageCount(itemID) or 0
        local have = haveBank + haveStorage
        local missing = min.count - have
        if missing < 0 then missing = 0 end

        if not onlyMissing or missing > 0 then
            local invEntry = g.inventory.items[itemID]
            table.insert(list, {
                itemID = itemID,
                itemName = (invEntry and invEntry.itemName) or min.itemName,
                itemLink = (invEntry and invEntry.itemLink) or min.itemLink,
                itemQuality = invEntry and invEntry.itemQuality,
                required = min.count,
                have = have,
                haveBank = haveBank,
                haveStorage = haveStorage,
                missing = missing,
            })
        end
    end

    -- Groesste Luecke zuerst - danach alphabetisch, damit die Reihenfolge
    -- bei gleichem Fehlstand stabil bleibt.
    table.sort(list, function(a, b)
        if a.missing == b.missing then
            return (a.itemName or "") < (b.itemName or "")
        end
        return a.missing > b.missing
    end)

    return list
end

-- ============================================================
-- Lager-Twinks (seit 1.3)
--
-- Charaktere des eigenen Accounts, die als Lager dienen (typisch vor dem
-- Kauf eines Bankfachs). Grindkeep liest deren Taschen und Bank selbst
-- aus (Storage.lua). Gespeichert ACCOUNT-weit, nicht je Gilde: ein
-- Lager-Twink gehoert dem Spieler, und alle Charaktere teilen dieselben
-- gespeicherten Daten. Wie beim Bestand ist jede Erfassung eine
-- vollstaendige Momentaufnahme - Taschen und Bank getrennt, weil die
-- Bank nur lesbar ist, solange sie geoeffnet ist.
-- ============================================================
local function StorageRoot()
    GrindkeepDB.storage = GrindkeepDB.storage or {}
    return GrindkeepDB.storage
end

-- "Name-Realm" des eingeloggten Charakters
function Database.CharKey()
    local name = UnitName and UnitName("player")
    if not name then return nil end
    local realm = NormalizeRealm(GetNormalizedRealmName and GetNormalizedRealmName())
    return realm and (name .. "-" .. realm) or name
end

local function CopyItems(items)
    local out = {}
    for itemID, e in pairs(items or {}) do
        if type(itemID) == "number" and (e.count or 0) > 0 then
            out[itemID] = {
                count = math.floor(e.count),
                itemName = e.itemName,
                itemLink = e.itemLink,
                itemQuality = e.itemQuality,
            }
        end
    end
    return out
end

function Database.IsStorageChar(key)
    local c = key and StorageRoot()[key]
    return c ~= nil and c.enabled == true
end

function Database.SetStorageChar(key, enabled)
    if not key then return false end
    local root = StorageRoot()
    if enabled then
        local c = root[key] or { bags = {}, bank = {} }
        c.enabled = true
        -- Realm nur abtrennen, wenn es wirklich einer ist (Nachnamen koennen
        -- Bindestriche enthalten, siehe Names.lua)
        c.name = c.name or (_G.GrindkeepNames and _G.GrindkeepNames.Base(key)) or key
        root[key] = c
    elseif root[key] then
        root[key].enabled = false
    end
    return true
end

-- Ganz entfernen (samt Daten), z.B. fuer einen geloeschten Charakter
function Database.RemoveStorageChar(key)
    local root = StorageRoot()
    if not key or not root[key] then return false end
    root[key] = nil
    return true
end

-- part: "bags" oder "bank"
function Database.SetStorageSnapshot(key, part, items)
    if part ~= "bags" and part ~= "bank" then return false end
    local c = key and StorageRoot()[key]
    if not c or not c.enabled then return false end
    c[part] = CopyItems(items)
    c[part .. "At"] = Database.Now()
    -- Zu welcher Gilde / welchem Realm gehoert der Twink? Damit zaehlt er
    -- nur dort mit und nicht bei Charakteren anderer Gilden des Accounts.
    c.guildKey = GuildKey()
    c.realm = NormalizeRealm(GetNormalizedRealmName and GetNormalizedRealmName())
    return true
end

-- Gehoert ein Lager-Twink zur Gilde des eingeloggten Charakters? Twinks
-- ohne Gilde zaehlen fuer alle Charaktere desselben Realms.
local function BelongsHere(c)
    local myGuild = GuildKey()
    local myRealm = NormalizeRealm(GetNormalizedRealmName and GetNormalizedRealmName())
    if c.guildKey then return c.guildKey == myGuild end
    if c.realm and myRealm then return c.realm == myRealm end
    return true
end

local function EnabledStorage()
    local list = {}
    for key, c in pairs(StorageRoot()) do
        if c.enabled and BelongsHere(c) then table.insert(list, { key = key, data = c }) end
    end
    table.sort(list, function(a, b) return a.key < b.key end)
    return list
end

-- Uebersicht der Lager-Twinks fuer die Anzeige
function Database.GetStorageChars(includeAll)
    local out = {}
    local source = EnabledStorage()
    if includeAll then
        source = {}
        for key, c in pairs(StorageRoot()) do table.insert(source, { key = key, data = c }) end
        table.sort(source, function(a, b) return a.key < b.key end)
    end
    for _, e in ipairs(source) do
        local kinds = 0
        for _ in pairs(e.data.bags or {}) do kinds = kinds + 1 end
        for _ in pairs(e.data.bank or {}) do kinds = kinds + 1 end
        table.insert(out, {
            key = e.key,
            name = e.data.name or e.key,
            bagsAt = e.data.bagsAt,
            bankAt = e.data.bankAt,
            itemKinds = kinds,
        })
    end
    return out
end

-- Menge eines Gegenstands auf allen Lager-Twinks; zweiter Wert: je Twink
function Database.GetStorageCount(itemID)
    if not itemID then return 0, {} end
    local total, sources = 0, {}
    for _, e in ipairs(EnabledStorage()) do
        local n = 0
        local b = e.data.bags and e.data.bags[itemID]
        local k = e.data.bank and e.data.bank[itemID]
        if b then n = n + (b.count or 0) end
        if k then n = n + (k.count or 0) end
        if n > 0 then
            total = total + n
            table.insert(sources, { name = e.data.name or e.key, count = n })
        end
    end
    return total, sources
end

-- Gildenbank + Lager-Twinks
function Database.GetTotalCount(itemID)
    local bank = Database.GetInventoryCount(itemID)
    local storage, sources = Database.GetStorageCount(itemID)
    return bank + storage, bank, storage, sources
end

-- Zusammengefasster Bestand. source: "all" (Standard) | "bank" | "storage"
function Database.GetCombinedInventory(source)
    source = source or "all"
    local byId = {}
    local function Add(itemID, e, bankCount, storageCount, sourceName)
        local row = byId[itemID]
        if not row then
            row = { itemID = itemID, count = 0, bankCount = 0, storageCount = 0, sources = {} }
            byId[itemID] = row
        end
        row.itemName = row.itemName or e.itemName
        row.itemLink = row.itemLink or e.itemLink
        row.itemQuality = row.itemQuality or e.itemQuality
        row.count = row.count + bankCount + storageCount
        row.bankCount = row.bankCount + bankCount
        row.storageCount = row.storageCount + storageCount
        if sourceName then
            local found
            for _, s in ipairs(row.sources) do
                if s.name == sourceName then s.count = s.count + bankCount + storageCount; found = true end
            end
            if not found then table.insert(row.sources, { name = sourceName, count = bankCount + storageCount }) end
        end
    end

    if source ~= "storage" then
        local g = GetGuildData()
        if g then
            for itemID, e in pairs(g.inventory.items) do
                if (e.count or 0) > 0 then Add(itemID, e, e.count, 0, "@bank") end
            end
        end
    end
    if source ~= "bank" then
        for _, st in ipairs(EnabledStorage()) do
            local name = st.data.name or st.key
            for _, part in ipairs({ "bags", "bank" }) do
                for itemID, e in pairs(st.data[part] or {}) do
                    Add(itemID, e, 0, e.count or 0, name)
                end
            end
        end
    end

    local list = {}
    for _, row in pairs(byId) do table.insert(list, row) end
    table.sort(list, function(a, b)
        if a.count ~= b.count then return a.count > b.count end
        return (a.itemName or "") < (b.itemName or "")
    end)
    return list
end

-- ============================================================
-- Sammelliste (seit 1.3)
--
-- Was die Gilde gerade sammelt: "100x Friedensblume fuer den Raid".
-- Mit Gegenstand zaehlt Grindkeep den Stand selbst (Gildenbank +
-- Lager-Twinks); ohne Gegenstand (freier Text, z.B. "Gold fuer Fach 2")
-- wird der Stand von Hand gesetzt. Je Gilde gespeichert.
-- ============================================================
local COLLECT_TEXT_MAX = 80
local COLLECT_NOTE_MAX = 100
local COLLECT_TARGET_MAX = 1000000

local function CollectData(g)
    g.collect = g.collect or { entries = {}, nextId = 0 }
    g.collect.entries = g.collect.entries or {}
    g.collect.nextId = g.collect.nextId or 0
    return g.collect
end

-- Auf hoechstens maxLen Bytes kuerzen, ohne ein Umlaut-Zeichen (UTF-8,
-- mehrere Bytes) mittendrin zu zerschneiden.
local function Utf8Cut(text, maxLen)
    if #text <= maxLen then return text end
    local cut = maxLen
    while cut > 0 do
        local b = text:byte(cut + 1)
        if not b or b < 0x80 or b >= 0xC0 then break end
        cut = cut - 1
    end
    return text:sub(1, cut)
end
Database.Utf8Cut = Utf8Cut

local function CleanText(text, maxLen)
    if type(text) ~= "string" then return nil end
    text = text:gsub("[\r\n\t]", " ")
    -- Symbole (Qualitaetsstufen, Texturen) und Farben entfernen, dann alle
    -- uebrigen "|" entschaerfen - es sind WoW-Steuerzeichen
    text = text:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("|", "/"):gsub("^%s+", ""):gsub("%s+$", "")
    return Utf8Cut(text, maxLen)
end

local function ValidTarget(n)
    n = tonumber(n)
    if not n then return nil end
    n = math.floor(n)
    if n < 1 or n > COLLECT_TARGET_MAX then return nil end
    return n
end

-- fields: itemID?, itemName, itemLink?, target, note?
function Database.AddCollectEntry(fields)
    local g = GetGuildData()
    if not g or type(fields) ~= "table" then return nil end
    local target = ValidTarget(fields.target)
    if not target then return nil end
    local itemID = tonumber(fields.itemID)
    local name = CleanText(fields.itemName, COLLECT_TEXT_MAX)
    if not itemID and (not name or name == "") then return nil end
    local c = CollectData(g)
    c.nextId = c.nextId + 1
    local entry = {
        id = c.nextId,
        itemID = itemID,
        itemName = name ~= "" and name or nil,
        itemLink = itemID and type(fields.itemLink) == "string" and fields.itemLink or nil,
        target = target,
        note = CleanText(fields.note, COLLECT_NOTE_MAX),
        manualHave = 0,
        done = false,
        createdAt = Database.Now(),
        createdBy = UnitName and UnitName("player") or nil,
    }
    if entry.note == "" then entry.note = nil end
    table.insert(c.entries, entry)
    return entry.id
end

local function FindCollect(id)
    local g = GetGuildData()
    if not g then return nil end
    for i, e in ipairs(CollectData(g).entries) do
        if e.id == id then return e, i, g end
    end
    return nil
end

-- fields: target?, note?, done?, manualHave?
function Database.UpdateCollectEntry(id, fields)
    local e = FindCollect(id)
    if not e or type(fields) ~= "table" then return false end
    if fields.target ~= nil then
        local t = ValidTarget(fields.target)
        if not t then return false end
        e.target = t
    end
    if fields.manualHave ~= nil then
        local n = tonumber(fields.manualHave)
        if not n or n < 0 then return false end
        e.manualHave = math.min(math.floor(n), COLLECT_TARGET_MAX)
    end
    if fields.note ~= nil then
        local note = CleanText(fields.note, COLLECT_NOTE_MAX)
        e.note = (note and note ~= "") and note or nil
    end
    if fields.done ~= nil then
        e.done = fields.done and true or false
        e.doneAt = e.done and Database.Now() or nil
    end
    return true
end

function Database.RemoveCollectEntry(id)
    local e, i, g = FindCollect(id)
    if not e then return false end
    table.remove(CollectData(g).entries, i)
    return true
end

-- Liste mit berechnetem Stand. includeDone: erledigte mit anzeigen.
function Database.GetCollectList(includeDone)
    local g = GetGuildData()
    if not g then return {} end
    local out = {}
    for _, e in ipairs(CollectData(g).entries) do
        if includeDone or not e.done then
            local have, bank, storage, sources
            if e.itemID then
                have, bank, storage, sources = Database.GetTotalCount(e.itemID)
                local inv = g.inventory.items[e.itemID]
                if not e.itemName and inv and inv.itemName then e.itemName = inv.itemName end
                if not e.itemLink and inv and inv.itemLink then e.itemLink = inv.itemLink end
            else
                have = e.manualHave or 0
            end
            local missing = math.max(0, e.target - have)
            table.insert(out, {
                id = e.id, itemID = e.itemID, itemName = e.itemName, itemLink = e.itemLink,
                target = e.target, note = e.note, done = e.done, createdAt = e.createdAt,
                createdBy = e.createdBy, manual = e.itemID == nil,
                have = have, haveBank = bank or 0, haveStorage = storage or 0, sources = sources or {},
                missing = missing, reached = missing == 0,
                progress = math.min(1, have / e.target),
            })
        end
    end
    -- Offene vor erledigten, sonst in der Reihenfolge des Anlegens
    table.sort(out, function(a, b)
        local ad, bd = a.done and 1 or 0, b.done and 1 or 0
        if ad ~= bd then return ad < bd end
        return (a.id or 0) < (b.id or 0)
    end)
    return out
end

Database.COLLECT_TEXT_MAX = COLLECT_TEXT_MAX
Database.COLLECT_NOTE_MAX = COLLECT_NOTE_MAX

-- ============================================================
-- Aufbewahrungsdauer
--
-- Transaktionen und Loot werden sonst endlos angehaengt. Nach Monaten
-- waechst die Datei, das Einloggen dauert laenger und ein Export kann
-- das Spiel kurz einfrieren. Eintraege, die aelter als die eingestellte
-- Aufbewahrungsdauer sind, werden deshalb beim Einloggen entfernt
-- (0 Tage = nie loeschen). Bestand und Mindestbestaende sind davon nicht
-- betroffen, sie sind immer nur eine Momentaufnahme.
-- ============================================================
local function PruneGuild(g, cutoff)
    local removed = 0

    local keptTx = {}
    for _, tx in ipairs(g.transactions) do
        if (tx.ts or 0) >= cutoff then
            table.insert(keptTx, tx)
        else
            removed = removed + 1
        end
    end

    local keptLoot = {}
    for _, entry in ipairs(g.loot) do
        if (entry.ts or 0) >= cutoff then
            table.insert(keptLoot, entry)
        else
            removed = removed + 1
        end
    end

    if removed > 0 then
        g.transactions = keptTx
        g.loot = keptLoot
        RebuildSummaries(g)
        -- Wartelisten fuer Item-Infos auf noch vorhandene Eintraege kuerzen
        for itemID, ids in pairs(g.pendingItems) do
            local keep = {}
            for _, id in ipairs(ids) do
                if g.transactionsById[id] then table.insert(keep, id) end
            end
            g.pendingItems[itemID] = (#keep > 0) and keep or nil
        end
    end
    return removed
end

function Database.PruneOldEntries(days, nowTs)
    days = tonumber(days) or 0
    if days <= 0 or not GrindkeepDB.guilds then return 0 end
    local cutoff = (nowTs or Database.Now()) - days * 86400
    local total = 0
    for key in pairs(GrindkeepDB.guilds) do
        total = total + PruneGuild(EnsureGuildData(key), cutoff)
    end
    return total
end

-- ============================================================
-- Start: wird von Core.lua beim ADDON_LOADED dieses Addons aufgerufen,
-- also sobald die gespeicherten Daten wirklich geladen sind.
-- ============================================================
local SCHEMA_VERSION = 3 -- 3: Vorgangszaehler je Spieler (txCount)

function Database.OnLoad()
    GrindkeepDB = GrindkeepDB or {}
    GrindkeepDB.guilds = GrindkeepDB.guilds or {}
    GrindkeepDB.storage = GrindkeepDB.storage or {}

    -- Uebernahme vom Vorgaenger "GrindLedger" (identisches Schema) -
    -- greift nur, wenn dessen Daten ebenfalls geladen sind.
    if not GrindkeepDB.migratedFromGrindLedger
        and type(GrindLedgerDB) == "table" and type(GrindLedgerDB.guilds) == "table" then
        for key, guildData in pairs(GrindLedgerDB.guilds) do
            if GrindkeepDB.guilds[key] == nil then
                GrindkeepDB.guilds[key] = guildData
            end
        end
        GrindkeepDB.migratedFromGrindLedger = true
    end

    -- Umstieg von Versionen bis 0.9.x: Twink-Ketten entwirren, Summen mit
    -- dem neuen, sprachneutralen Kategorie-Schluessel neu aufbauen, alte
    -- Abgleich-Listen des frueheren Scan-Verfahrens entfernen.
    if (GrindkeepDB.schemaVersion or 1) < SCHEMA_VERSION then
        for key in pairs(GrindkeepDB.guilds) do
            local g = EnsureGuildData(key)
            NormalizeAlts(g)
            RebuildSummaries(g)
            g.scanState = nil
        end
        GrindkeepDB.schemaVersion = SCHEMA_VERSION
    end

    if GrindkeepDB.pruneFromNextLogin then
        return Database.PruneOldEntries(Database.GetSetting("retentionDays"))
    end
    -- Erster Start mit Aufbewahrungsdauer: erst ab dem naechsten Login
    -- aufraeumen, damit niemand beim Update ungefragt Verlauf verliert.
    GrindkeepDB.pruneFromNextLogin = true
    return 0
end

function Database.ResetGuildData()
    local key = GuildKey()
    if key and GrindkeepDB.guilds then
        GrindkeepDB.guilds[key] = nil
    end
end

-- ============================================================
-- Account-weite Einstellungen (Optionsfenster, siehe Options.lua) -
-- bewusst getrennt von den Gildendaten oben unter einem eigenen
-- "settings"-Schluessel, damit beides klar auseinandergehalten wird.
-- ============================================================
Database.SettingDefaults = {
    autoScanOnOpen   = true, -- Gildenbank oeffnen loest automatisch einen Scan aus
    autoStockScan    = true, -- nach dem Log-Scan zusaetzlich den Bestand der Faecher einlesen
    showMinimapButton = true, -- eigener Knopf an der Minimap
    minimapAngle     = 215,  -- Position des Minimap-Knopfs (Grad auf dem Kreis)
    showBankTabButton = true, -- eigener Reiter im Gildenbank-Fenster neben "Info"
    fontChoice       = "default", -- Schriftart der Fenster (siehe Style.lua)
    fontScale        = 1,    -- Schriftgroesse als Faktor auf die Originalgroessen
    windowOpacity    = 1,    -- Fenster-Transparenz (1 = undurchsichtig)
    theme            = "classic", -- Design des Hauptfensters (siehe Theme.lua)
    accent           = "theme",   -- Akzentfarbe: "theme" = passend zum Design
    scanChatMessages = true, -- "Scan gestartet/abgeschlossen" im Chat anzeigen
    syncEnabled      = true, -- Twink-Zuordnungen automatisch mit der Gilde abgleichen
    syncTrustedRank  = 2,    -- Rang-Index (0 = hoechster Rang), bis zu dem Zuordnungen automatisch vertraut wird
    lootTrackingEnabled = false, -- Loot in Schlachtzuegen automatisch mitschreiben (CHAT_MSG_LOOT) - bewusst erst nach Einschalten aktiv
    lootSyncEnabled      = true, -- Loot-Eintraege mit der Gilde abgleichen (nur wirksam, wenn die Erfassung an ist; gleiche Vertrauensgrenze wie syncTrustedRank)
    lootMinQuality       = 3,    -- Mindest-Item-Qualitaet fuer die Erfassung (0=grau, 1=weiss, 2=gruen, 3=blau, 4=lila, 5=orange)
    lootRaidOnly         = true, -- nur in Schlachtzuegen erfassen, nicht in 5er-Gruppen
    retentionDays        = 365,  -- Eintraege aelter als so viele Tage beim Einloggen entfernen (0 = nie)
}

function Database.GetSetting(key)
    GrindkeepDB.settings = GrindkeepDB.settings or {}
    local value = GrindkeepDB.settings[key]
    if value == nil then return Database.SettingDefaults[key] end
    return value
end

function Database.SetSetting(key, value)
    GrindkeepDB.settings = GrindkeepDB.settings or {}
    GrindkeepDB.settings[key] = value
end

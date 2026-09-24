--[[
    Grindkeep - Comm.lua

    Datenaustausch zwischen Clients, in zwei unabhaengigen Wegen:

    1) Automatischer Abgleich ueber das Gilden-Addon-Netzwerk
       (C_ChatInfo.SendAddonMessage): Twink-Zuordnungen und - falls die
       Loot-Erfassung eingeschaltet ist - Raid-Beute. Kleine, seltene
       Nachrichten.

    2) Manueller Export/Import der Transaktions- und Loot-Historie ueber
       ein Textfenster zum Kopieren und Einfuegen. Kein Netzwerkverkehr,
       ein Mensch entscheidet aktiv, wessen Daten er uebernimmt.

    ================================================================
    SICHERHEIT
    ================================================================
    Addon-Nachrichten sind nicht authentifiziert: jeder Client kann mit
    unserem Praefix irgendetwas behaupten. Deshalb gilt fuer JEDE
    eingehende Nachricht:

    - Der Rang des Absenders wird frisch im EIGENEN Gildenroster
      nachgeschlagen, nie aus der Nachricht uebernommen.
    - Namen werden mit Realm verglichen (Names.lua). Ein Anhang "-Xyz"
      zaehlt nur als Realm, wenn es der eigene oder ein verbundener ist -
      ein Namensvetter von einem fremden Realm bekommt so nie die Rechte
      eines Offiziers. Fehlt der Realm auf einer Seite (Forever-Roster),
      gilt bei mehreren Treffern der niedrigste Rang.
    - Zuordnungen und Loot werden nur ueber den Gildenkanal akzeptiert.
      Eine Sammelantwort (ALTSYNC) nur als Fluesternachricht und nur,
      wenn wir kurz vorher selbst danach gefragt haben.
    - Alles wird auf Laenge und Plausibilitaet geprueft und begrenzt,
      damit fehlerhafte oder boesartige Nachrichten weder Lua-Fehler noch
      endlos wachsende Daten erzeugen koennen.
]]

local DB = _G.GrindkeepDatabase
local L = _G.GrindkeepLocale
local PREFIX = "Grindkeep"   -- <= 16 Zeichen, Pflicht von Blizzard
local MAX_MSG = 250          -- hartes Limit von Blizzard: 255 Byte je Nachricht
local CHUNK_SIZE = 200       -- Nutzlast je Teilnachricht beim Sammelabgleich
local MAX_CHUNKS = 200       -- mehr Teile nimmt ein Empfaenger nicht an
local SEND_INTERVAL = 1.0    -- Sekunden zwischen zwei Teilnachrichten (Blizzard drosselt sonst)
local MAX_NAME_LEN = 64
local MAX_ALTS = 1000        -- Obergrenze fuer uebernommene Twink-Zuordnungen
local ALTSYNC_WINDOW = 300   -- Sekunden nach eigener Anfrage, in denen Antworten gelten

local function Print(msg)
    print("|cff2ecc71[Grindkeep]|r " .. tostring(msg))
end

-- ============================================================
-- Namen (Zerlegen und Vergleichen: siehe Names.lua)
-- ============================================================
local Names = _G.GrindkeepNames

-- Anzeigename ohne (eigenen oder verbundenen) Realm
local function ShortName(name)
    return Names.Base(name)
end

local function SameCharacter(a, b)
    return (Names.Same(a, b))
end

local function ValidName(name)
    return type(name) == "string" and name ~= "" and #name <= MAX_NAME_LEN
        and not name:find("[|=\30\31]")
end

-- ============================================================
-- Rang-Pruefung: IMMER live gegen das eigene Roster
-- ============================================================
local function TrustedRankMax()
    return DB.GetSetting("syncTrustedRank")
end

-- Rang aus dem eigenen Roster. Auf Forever liefert das Roster Namen ohne
-- Realm - passen dann mehrere Eintraege (gleicher Name auf verbundenen
-- Realms), zaehlt der niedrigste Rang (hoechster Index): im Zweifel
-- weniger Vertrauen statt mehr.
local function RosterEntry(name)
    if not IsInGuild or not IsInGuild() then return nil end
    if type(name) ~= "string" or name == "" then return nil end
    local num = GetNumGuildMembers and GetNumGuildMembers() or 0
    local exactRank, exactOnline, looseRank, looseOnline
    for i = 1, num do
        local fullName, _, rankIndex, _, _, _, _, _, online = GetGuildRosterInfo(i)
        if fullName and rankIndex then
            local same, exact = Names.Same(fullName, name)
            if same and exact then
                if not exactRank or rankIndex > exactRank then exactRank, exactOnline = rankIndex, online end
            elseif same then
                if not looseRank or rankIndex > looseRank then looseRank, looseOnline = rankIndex, online end
            end
        end
    end
    if exactRank then return exactRank, exactOnline end
    return looseRank, looseOnline
end

local function IsTrusted(name)
    local rank = RosterEntry(name)
    return rank ~= nil and rank <= TrustedRankMax()
end

local function IsGuildMember(name)
    return RosterEntry(name) ~= nil
end

local function MyFullName()
    return Names.Me()
end

local function IAmTrusted()
    return IsTrusted(MyFullName())
end

-- ============================================================
-- Senden
-- ============================================================
local function SendMsg(payload, distribution, target)
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
    if #payload > 255 then return false end
    local ok, result = pcall(C_ChatInfo.SendAddonMessage, PREFIX, payload, distribution, target)
    if not ok then return false end
    -- Neuere Clients geben einen Ergebniscode zurueck (0 = erfolgreich),
    -- aeltere nichts oder true.
    return result == nil or result == true or result == 0
end

-- ============================================================
-- Base64 fuer den Export (nur ein copy-paste-sicheres Alphabet, keine
-- Verschluesselung). Arbeitet in Dreierbloecken statt Bit fuer Bit -
-- auch grosse Exporte bleiben dadurch schnell.
-- ============================================================
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, 64 do B64_INDEX[B64:sub(i, i)] = i - 1 end

local function Base64Encode(data)
    local out = {}
    local len = #data
    for i = 1, len, 3 do
        local a, b, c = data:byte(i, i + 2)
        local n = a * 65536 + (b or 0) * 256 + (c or 0)
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        out[#out + 1] = B64:sub(c1 + 1, c1 + 1) .. B64:sub(c2 + 1, c2 + 1)
            .. (b and B64:sub(c3 + 1, c3 + 1) or "=")
            .. (c and B64:sub(c4 + 1, c4 + 1) or "=")
    end
    return table.concat(out)
end

local function Base64Decode(data)
    data = data:gsub("[^%w%+/=]", "")
    local out = {}
    for i = 1, #data, 4 do
        local s1, s2, s3, s4 = data:sub(i, i), data:sub(i + 1, i + 1), data:sub(i + 2, i + 2), data:sub(i + 3, i + 3)
        local v1, v2 = B64_INDEX[s1], B64_INDEX[s2]
        if not v1 or not v2 then break end
        local v3, v4 = B64_INDEX[s3], B64_INDEX[s4]
        local n = v1 * 262144 + v2 * 4096 + (v3 or 0) * 64 + (v4 or 0)
        out[#out + 1] = string.char(math.floor(n / 65536) % 256)
        if v3 then out[#out + 1] = string.char(math.floor(n / 256) % 256) end
        if v4 then out[#out + 1] = string.char(n % 256) end
    end
    return table.concat(out)
end

-- ============================================================
-- Textfenster zum Kopieren/Einfuegen
--
-- Eigenes Fenster statt Blizzards StaticPopup: das Popup-Eingabefeld
-- heisst je nach Client "editBox" oder "EditBox" (daran sind Export und
-- Import auf WoW Forever abgestuerzt), es wird von allen Addons geteilt
-- (Mehrzeilig-Einstellungen blieben haengen) und hat keine Scrollleiste.
-- ============================================================
local TextWindow

local function BuildTextWindow()
    local f = CreateFrame("Frame", "GrindkeepTextWindow", UIParent, "BackdropTemplate")
    f:SetSize(540, 380)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    if _G.BACKDROP_DARK_DIALOG_32_32 then
        f:SetBackdrop(_G.BACKDROP_DARK_DIALOG_32_32)
    else
        f:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
        f:SetBackdropColor(0.07, 0.07, 0.09, 0.95)
        f:SetBackdropBorderColor(0.16, 0.18, 0.2, 1)
    end
    f:Hide()
    tinsert(UISpecialFrames, "GrindkeepTextWindow")

    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.title:SetPoint("TOPLEFT", 20, -18)
    f.title:SetPoint("TOPRIGHT", -40, -18)
    f.title:SetJustifyH("LEFT")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -6, -6)

    local scroll = CreateFrame("ScrollFrame", "GrindkeepTextWindowScroll", f, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 20, -44)
    scroll:SetPoint("BOTTOMRIGHT", -40, 52)

    local edit = CreateFrame("EditBox", nil, scroll)
    edit:SetMultiLine(true)
    edit:SetAutoFocus(false)
    edit:SetMaxLetters(0)
    edit:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlightSmall)
    edit:SetWidth(470)
    edit:SetScript("OnEscapePressed", function() f:Hide() end)
    if _G.ScrollingEdit_OnCursorChanged then
        edit:SetScript("OnCursorChanged", _G.ScrollingEdit_OnCursorChanged)
    end
    scroll:SetScrollChild(edit)
    -- Klick irgendwo in die Flaeche setzt den Fokus ins Textfeld
    scroll:EnableMouse(true)
    scroll:SetScript("OnMouseDown", function() edit:SetFocus() end)
    f.edit = edit

    f.accept = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.accept:SetSize(130, 24)
    f.accept:SetPoint("BOTTOMRIGHT", -150, 18)

    f.cancel = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.cancel:SetSize(120, 24)
    f.cancel:SetPoint("BOTTOMRIGHT", -20, 18)
    f.cancel:SetScript("OnClick", function() f:Hide() end)

    if _G.GrindkeepStyle then _G.GrindkeepStyle.RegisterAndApply(f) end
    return f
end

-- text: vorbelegter Inhalt (Export) oder nil (Import)
-- onAccept: bei Import die Funktion, die den eingefuegten Text bekommt
local function ShowTextWindow(title, text, acceptLabel, onAccept)
    TextWindow = TextWindow or BuildTextWindow()
    local f = TextWindow
    f.title:SetText(title)
    f.edit:SetText(text or "")
    if onAccept then
        f.accept:SetText(acceptLabel or OKAY)
        f.accept:SetScript("OnClick", function()
            local value = f.edit:GetText()
            f:Hide()
            onAccept(value)
        end)
        f.accept:Show()
        f.cancel:SetText(CANCEL)
    else
        f.accept:Hide()
        f.cancel:SetText(CLOSE)
    end
    f:Show()
    f.edit:SetFocus()
    if text and text ~= "" then f.edit:HighlightText() end
end

-- ============================================================
-- Teilnachrichten (fuer den Sammelabgleich der Twink-Zuordnungen)
-- ============================================================
local pendingChunks = {} -- [sender] = { id, total, have, parts, started }

-- Teilnachrichten nacheinander mit Abstand senden: Blizzard drosselt
-- Addon-Nachrichten je Praefix, ein ganzer Schwall auf einmal wuerde
-- ab etwa der zehnten Nachricht verworfen.
local function SendChunked(kind, serialized, distribution, target)
    if not serialized or serialized == "" then return end
    local id = tostring(math.random(100000, 999999))
    local total = math.ceil(#serialized / CHUNK_SIZE)
    if total > MAX_CHUNKS then return end
    local i = 0
    local function sendNext()
        i = i + 1
        if i > total then return end
        local chunk = serialized:sub((i - 1) * CHUNK_SIZE + 1, i * CHUNK_SIZE)
        SendMsg(string.format("%s:%s:%d/%d:%s", kind, id, i, total, chunk), distribution, target)
        if i < total then C_Timer.After(SEND_INTERVAL, sendNext) end
    end
    sendNext()
end

-- Liefert den vollstaendigen Text, sobald alle Teile da sind, sonst nil.
local function ReceiveChunk(sender, id, seq, total, chunk)
    seq, total = tonumber(seq), tonumber(total)
    if not seq or not total or total < 1 or total > MAX_CHUNKS or seq < 1 or seq > total then
        return nil
    end

    local now = GetTime and GetTime() or time()
    local buf = pendingChunks[sender]
    if not buf or buf.id ~= id or buf.total ~= total or (now - buf.started) > (total * SEND_INTERVAL + 60) then
        buf = { id = id, total = total, have = 0, parts = {}, started = now }
        pendingChunks[sender] = buf
    end
    if not buf.parts[seq] then
        buf.parts[seq] = chunk
        buf.have = buf.have + 1
    end
    if buf.have == total then
        pendingChunks[sender] = nil
        return table.concat(buf.parts, "", 1, total)
    end
    return nil
end

-- ============================================================
-- 1) Twink-Zuordnungen
-- ============================================================
local lastAltRequest = 0

local function BroadcastAltAssignment(twink, main)
    if not DB.GetSetting("syncEnabled") then return end
    if not ValidName(twink) or not ValidName(main) then return end
    if not IAmTrusted() then return end -- nur bis zur Vertrauensgrenze wird gesendet
    SendMsg(string.format("ALT:%s=%s", twink, main), "GUILD")
end

local function BroadcastAltRemoval(twink)
    if not DB.GetSetting("syncEnabled") then return end
    if not ValidName(twink) then return end
    if not IAmTrusted() then return end
    SendMsg("ALTDEL:" .. twink, "GUILD")
end

local function SerializeAlts()
    local g = DB.GetGuildData()
    if not g then return "" end
    local parts = {}
    for twink, main in pairs(g.alts) do
        if ValidName(twink) and ValidName(main) then
            table.insert(parts, twink .. "=" .. main)
        end
    end
    return table.concat(parts, "|")
end

local function AltCount()
    local g = DB.GetGuildData()
    local n = 0
    if g then for _ in pairs(g.alts) do n = n + 1 end end
    return n
end

local function ApplyAltDump(serialized)
    local applied = 0
    local count = AltCount()
    for pair in serialized:gmatch("[^|]+") do
        local twink, main = pair:match("^(.-)=(.+)$")
        if ValidName(twink) and ValidName(main) and count < MAX_ALTS then
            if DB.GetMain(twink) ~= DB.GetMain(main) and DB.SetAlt(twink, main) then
                applied = applied + 1
                count = count + 1
            end
        end
    end
    return applied
end

local function OnAltMessage(sender, message)
    if not DB.GetSetting("syncEnabled") or not IsTrusted(sender) then return end
    local twink, main = message:match("^ALT:(.-)=(.+)$")
    if not ValidName(twink) or not ValidName(main) then return end
    if AltCount() >= MAX_ALTS then return end
    if DB.SetAlt(twink, main) then
        Print(string.format(L["COMM_ALT_RECEIVED"], ShortName(sender), twink, DB.GetMain(twink)))
        if _G.GrindkeepUI then _G.GrindkeepUI.Refresh() end
    end
end

local function OnAltRemoval(sender, message)
    if not DB.GetSetting("syncEnabled") or not IsTrusted(sender) then return end
    local twink = message:match("^ALTDEL:(.+)$")
    if ValidName(twink) and DB.ClearAlt(twink) then
        Print(string.format(L["COMM_ALT_REMOVED_RECEIVED"], ShortName(sender), twink))
        if _G.GrindkeepUI then _G.GrindkeepUI.Refresh() end
    end
end

-- Wer beantwortet eine Anfrage? Moeglichst nur EIN Mitglied: Jedes
-- vertrauenswuerdige Mitglied mit Grindkeep wartet eine Weile (hoeherer
-- Rang = kuerzer, dazu etwas Zufall). Wer zuerst dran ist, kuendigt seine
-- Antwort im Gildenkanal an ("ALTANS:<Name>") - alle anderen verzichten
-- dann. Frueher antworteten alle Offiziere gleichzeitig, bei jeder
-- Anmeldung jedes Mitglieds.
local pendingAnswers = {} -- [Anfragender] = true, solange noch niemand geantwortet hat
local lastAnswered = {}   -- [Anfragender] = Zeitpunkt der letzten eigenen Antwort

-- Schluessel fuer die beiden Tabellen: derselbe Anfragende kann bei
-- verschiedenen Mitgliedern mit oder ohne Realm ankommen.
local function AnswerKey(name)
    local base, realm = Names.Split(name)
    base = base or tostring(name)
    return realm and (base .. "-" .. realm:lower()) or base
end

local function OnAltRequest(sender)
    if not DB.GetSetting("syncEnabled") then return end
    if not IsGuildMember(sender) or not IAmTrusted() then return end

    local now = time()
    local last = lastAnswered[AnswerKey(sender)]
    if last and now - last < 300 then return end
    if SerializeAlts() == "" then return end

    local myRank = RosterEntry(MyFullName()) or 0
    local delay = 1 + myRank * 2 + math.random(0, 20) / 10
    local key = AnswerKey(sender)
    pendingAnswers[key] = true
    C_Timer.After(delay, function()
        if not pendingAnswers[key] then return end -- jemand war schneller
        pendingAnswers[key] = nil
        lastAnswered[key] = time()
        SendMsg("ALTANS:" .. sender, "GUILD")
        SendChunked("ALTSYNC", SerializeAlts(), "WHISPER", sender)
    end)
end

local function OnAltAnswered(sender, message)
    local requester = message:match("^ALTANS:(.+)$")
    if requester and IsTrusted(sender) then
        pendingAnswers[AnswerKey(requester)] = nil
    end
end

local function OnAltSync(sender, id, seq, total, chunk)
    if not DB.GetSetting("syncEnabled") then return end
    if time() - lastAltRequest > ALTSYNC_WINDOW then return end -- nicht angefragt
    if not IsTrusted(sender) then return end
    local full = ReceiveChunk(sender, id, seq, total, chunk)
    if full then
        local applied = ApplyAltDump(full)
        if applied > 0 then
            Print(string.format(L["COMM_ALT_SYNC_RECEIVED"], applied, ShortName(sender)))
            if _G.GrindkeepUI then _G.GrindkeepUI.Refresh() end
        end
    end
end

-- ============================================================
-- 1b) Raid-Loot (nur wenn die Erfassung eingeschaltet ist)
-- ============================================================
-- Kompaktes Format, damit auch lange Itemlinks und Namen mit Realm unter
-- die 255-Byte-Grenze passen: statt Link UND Name wird nur der Itemcode
-- ("item:12345:...") uebertragen; der Empfaenger baut den Link daraus.
local US = "\31"

local function ItemStringFromLink(link)
    return type(link) == "string" and link:match("|H(item:[%-%d:]+)|h") or nil
end

local function BuildLootPayload(record)
    local itemString = ItemStringFromLink(record.itemLink) or (record.itemID and ("item:" .. record.itemID)) or ""
    local function build(itemPart, zone)
        return "LOOT:" .. table.concat({
            tostring(record.ts or DB.Now()), itemPart, tostring(record.itemQuality or ""),
            tostring(record.count or 1), record.recipient or "", zone or "",
        }, US)
    end
    local payload = build(itemString, record.raidName)
    if #payload > MAX_MSG then payload = build(itemString, "") end
    if #payload > MAX_MSG and record.itemID then payload = build("item:" .. record.itemID, "") end
    if #payload > MAX_MSG then return nil end
    return payload
end

local function ParseLootPayload(raw)
    local fields = {}
    for field in (raw .. US):gmatch("(.-)" .. US) do table.insert(fields, field) end
    if #fields < 6 then return nil end

    local ts = tonumber(fields[1])
    local itemString = fields[2]
    local itemID = tonumber(itemString:match("^item:(%d+)"))
    local count = tonumber(fields[4]) or 1
    local recipient = fields[5]
    if not ts or math.abs(ts - DB.Now()) > 86400 then return nil end
    if not itemID or count < 1 or count > 1000 then return nil end
    if recipient == "" or #recipient > MAX_NAME_LEN then return nil end

    local itemName, itemLink
    local GetInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
    if GetInfo then
        local ok, n, l = pcall(GetInfo, itemString)
        if ok then itemName, itemLink = n, l end
    end
    return {
        ts = ts,
        itemID = itemID,
        itemString = itemString,
        itemLink = itemLink,
        itemName = itemName,
        itemQuality = tonumber(fields[3]),
        count = count,
        recipient = recipient,
        raidName = fields[6] ~= "" and fields[6]:sub(1, 64) or nil,
    }
end

local function BroadcastLoot(record)
    if not DB.GetSetting("lootSyncEnabled") then return end
    if not IAmTrusted() then return end
    local payload = BuildLootPayload(record)
    if payload then SendMsg(payload, "GUILD") end
end

local function OnLootMessage(sender, message)
    if not DB.GetSetting("lootSyncEnabled") or not IsTrusted(sender) then return end
    local record = ParseLootPayload(message:sub(#"LOOT:" + 1))
    if not record then return end
    record.reportedBy = ShortName(sender)
    if _G.GrindkeepLoot then _G.GrindkeepLoot.OnRemoteLoot(record) end
end

-- ============================================================
-- 2) Manueller Export/Import
-- ============================================================
-- Feldtrenner als Steuerzeichen, weil Itemlinks selbst "|" enthalten.
local RS = "\30"

local function Field(v, maxLen)
    v = v == nil and "" or tostring(v)
    return v:gsub("[\30\31]", ""):sub(1, maxLen or 400)
end

local function SplitRecords(raw, minFields)
    local out = {}
    for record in (raw .. RS):gmatch("(.-)" .. RS) do
        if record ~= "" then
            local fields = {}
            for field in (record .. US):gmatch("(.-)" .. US) do table.insert(fields, field) end
            if #fields >= minFields then table.insert(out, fields) end
        end
    end
    return out
end

local function NilIfEmpty(v) if v == "" then return nil end return v end

-- Transaktionen ------------------------------------------------
local function SerializeTransactions()
    local g = DB.GetGuildData()
    if not g then return "" end
    local records = {}
    for _, tx in ipairs(g.transactions) do
        table.insert(records, table.concat({
            Field(tx.kind), Field(tx.action), Field(tx.player), Field(tx.ts),
            Field(tx.tab), Field(tx.tabName), Field(tx.amount),
            Field(tx.itemID), Field(tx.itemLink), Field(tx.count),
            Field(tx.itemName), Field(tx.itemQuality), Field(tx.itemType),
        }, US))
    end
    return table.concat(records, RS)
end

local function ParseTransaction(f)
    local kind, action, player = f[1], f[2], f[3]
    local ts = tonumber(f[4])
    if kind ~= "gold" and kind ~= "item" then return nil end
    if action == "" or #action > 20 then return nil end
    if player == "" or #player > MAX_NAME_LEN then return nil end
    if not ts or ts < 0 or ts > DB.Now() + 86400 then return nil end

    local tx = {
        kind = kind, action = action, player = player, ts = ts,
        tab = tonumber(f[5]), tabName = NilIfEmpty(f[6]),
        amount = tonumber(f[7]),
        itemID = tonumber(f[8]), itemLink = NilIfEmpty(f[9]), count = tonumber(f[10]),
        itemName = NilIfEmpty(f[11]), itemQuality = tonumber(f[12]), itemType = NilIfEmpty(f[13]),
    }
    if kind == "gold" and (not tx.amount or tx.amount < 0) then return nil end
    if kind == "item" and ((not tx.itemID and not tx.itemLink) or not tx.count or tx.count < 0) then return nil end
    return tx
end

-- Abgleich mit denselben Regeln wie beim Scan (Core.lua): gleicher Inhalt
-- und passende Zeit = derselbe Vorgang, jeder lokale Eintrag zaehlt nur
-- einmal. Was keinen Partner findet, wird uebernommen.
local function MergeImportedTransactions(imported)
    local g = DB.GetGuildData()
    if not g or not _G.GrindkeepMatcher then return 0 end
    local M = _G.GrindkeepMatcher

    table.sort(imported, function(a, b) return a.ts > b.ts end) -- neueste zuerst
    local visible = {}
    for i, tx in ipairs(imported) do
        visible[i] = { key = M.RecordKey(tx), ts = tx.ts }
    end
    local newIdx = M.FindNewEntries(visible, g.transactions, DB.Now())

    for n = #newIdx, 1, -1 do
        DB.AddTransaction(imported[newIdx[n]])
    end
    return #newIdx
end

local function Export()
    local raw = SerializeTransactions()
    if raw == "" then
        Print(L["COMM_EXPORT_NONE"])
        return
    end
    ShowTextWindow(L["COMM_EXPORT_TITLE"], Base64Encode(raw))
end

local Import -- Vorwaertsdeklaration

local function ShowImportDialog()
    ShowTextWindow(L["COMM_IMPORT_TITLE"], nil, L["COMM_IMPORT_BUTTON"], function(text) Import(text) end)
end

Import = function(base64String)
    if not base64String or base64String == "" then
        Print(L["COMM_IMPORT_NEED_STRING"])
        return
    end
    local ok, raw = pcall(Base64Decode, base64String)
    if not ok or not raw or raw == "" then
        Print(L["COMM_IMPORT_INVALID"])
        return
    end
    local imported, skipped = {}, 0
    for _, fields in ipairs(SplitRecords(raw, 13)) do
        local tx = ParseTransaction(fields)
        if tx then table.insert(imported, tx) else skipped = skipped + 1 end
    end
    if #imported == 0 then
        Print(L["COMM_IMPORT_EMPTY"])
        return
    end
    local added = MergeImportedTransactions(imported)
    Print(string.format(L["COMM_IMPORT_DONE"], added, #imported))
    if skipped > 0 then Print(string.format(L["COMM_IMPORT_SKIPPED"], skipped)) end
    if _G.GrindkeepUI then _G.GrindkeepUI.Refresh() end
end

-- Loot ----------------------------------------------------------
local function SerializeLootHistory()
    local g = DB.GetGuildData()
    if not g then return "" end
    local records = {}
    for _, e in ipairs(g.loot) do
        table.insert(records, table.concat({
            Field(e.ts), Field(e.itemID), Field(e.itemLink), Field(e.itemName),
            Field(e.itemQuality), Field(e.count), Field(e.recipient),
            Field(e.raidName), Field(e.lootMethod), Field(e.reportedBy),
        }, US))
    end
    return table.concat(records, RS)
end

local function ParseLootRecord(f)
    local ts = tonumber(f[1])
    local itemID = tonumber(f[2])
    local itemLink = NilIfEmpty(f[3])
    local recipient = NilIfEmpty(f[7])
    if not ts or ts < 0 or ts > DB.Now() + 86400 then return nil end
    if not itemID and not itemLink then return nil end
    if not recipient or #recipient > MAX_NAME_LEN then return nil end
    local count = tonumber(f[6]) or 1
    if count < 1 or count > 1000 then return nil end
    return {
        ts = ts, itemID = itemID, itemLink = itemLink, itemName = NilIfEmpty(f[4]),
        itemQuality = tonumber(f[5]), count = count, recipient = recipient,
        raidName = NilIfEmpty(f[8]), lootMethod = NilIfEmpty(f[9]), reportedBy = NilIfEmpty(f[10]),
    }
end

local function LootKey(e)
    return table.concat({ tostring(e.itemID or e.itemLink or "?"), ShortName(e.recipient), tostring(e.count or 1) }, US)
end
local function LootTolerance() return 180 end
if _G.GrindkeepMatcher then
    _G.GrindkeepMatcher.LootKey = LootKey
    _G.GrindkeepMatcher.LootTolerance = LootTolerance
end

local function MergeImportedLoot(imported)
    local g = DB.GetGuildData()
    if not g or not _G.GrindkeepMatcher then return 0 end
    table.sort(imported, function(a, b) return a.ts > b.ts end)
    local visible = {}
    for i, e in ipairs(imported) do visible[i] = { key = LootKey(e), ts = e.ts } end
    local newIdx = _G.GrindkeepMatcher.FindNewEntries(visible, g.loot, DB.Now(), LootKey, LootTolerance)
    for n = #newIdx, 1, -1 do
        DB.AddLoot(imported[newIdx[n]])
    end
    return #newIdx
end

local function ExportLoot()
    local raw = SerializeLootHistory()
    if raw == "" then
        Print(L["COMM_LOOT_EXPORT_NONE"])
        return
    end
    ShowTextWindow(L["COMM_LOOT_EXPORT_TITLE"], Base64Encode(raw))
end

local ImportLoot -- Vorwaertsdeklaration

local function ShowLootImportDialog()
    ShowTextWindow(L["COMM_LOOT_IMPORT_TITLE"], nil, L["COMM_IMPORT_BUTTON"], function(text) ImportLoot(text) end)
end

ImportLoot = function(base64String)
    if not base64String or base64String == "" then
        Print(L["COMM_LOOT_IMPORT_NEED_STRING"])
        return
    end
    local ok, raw = pcall(Base64Decode, base64String)
    if not ok or not raw or raw == "" then
        Print(L["COMM_IMPORT_INVALID"])
        return
    end
    local imported, skipped = {}, 0
    for _, fields in ipairs(SplitRecords(raw, 10)) do
        local e = ParseLootRecord(fields)
        if e then table.insert(imported, e) else skipped = skipped + 1 end
    end
    if #imported == 0 then
        Print(L["COMM_LOOT_IMPORT_EMPTY"])
        return
    end
    local added = MergeImportedLoot(imported)
    Print(string.format(L["COMM_LOOT_IMPORT_DONE"], added, #imported))
    if skipped > 0 then Print(string.format(L["COMM_IMPORT_SKIPPED"], skipped)) end
    if _G.GrindkeepLootUI then _G.GrindkeepLootUI.Refresh() end
end

-- ============================================================
-- Event-Handling
-- ============================================================
local function HandleAddonMessage(message, channel, sender)
    if SameCharacter(sender, MyFullName()) then return end -- eigenes Echo

    if message == "ALTREQ" then
        if channel == "GUILD" then OnAltRequest(sender) end
    elseif message:sub(1, 4) == "ALT:" then
        if channel == "GUILD" then OnAltMessage(sender, message) end
    elseif message:sub(1, 7) == "ALTDEL:" then
        if channel == "GUILD" then OnAltRemoval(sender, message) end
    elseif message:sub(1, 7) == "ALTANS:" then
        if channel == "GUILD" then OnAltAnswered(sender, message) end
    elseif message:sub(1, 8) == "ALTSYNC:" then
        if channel == "WHISPER" then
            local id, seq, total, chunk = message:match("^ALTSYNC:(%d+):(%d+)/(%d+):(.*)$")
            if id then OnAltSync(sender, id, seq, total, chunk) end
        end
    elseif message:sub(1, 5) == "LOOT:" then
        if channel == "GUILD" then OnLootMessage(sender, message) end
    end
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")

frame:SetScript("OnEvent", function(self, event, ...)
    if event == "PLAYER_LOGIN" then
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
        pcall(function()
            if C_GuildInfo and C_GuildInfo.GuildRoster then
                C_GuildInfo.GuildRoster()
            elseif GuildRoster then
                GuildRoster()
            end
        end)
        -- Einmalig kurz nach dem Login nach Twink-Zuordnungen fragen, die
        -- waehrend der eigenen Abwesenheit vergeben wurden.
        C_Timer.After(8, function()
            if DB.GetSetting("syncEnabled") and IsInGuild and IsInGuild() then
                lastAltRequest = time()
                SendMsg("ALTREQ", "GUILD")
            end
        end)
    elseif event == "CHAT_MSG_ADDON" then
        local prefix, message, channel, sender = ...
        if prefix ~= PREFIX then return end
        -- In Instanzen koennen neuere Clients Inhalte als geheime Werte
        -- liefern; damit darf nicht gerechnet werden.
        if issecretvalue and (issecretvalue(message) or issecretvalue(sender)) then return end
        if type(message) ~= "string" or type(sender) ~= "string" then return end
        -- Eine fehlerhafte Nachricht darf nie einen Lua-Fehler ausloesen.
        pcall(HandleAddonMessage, message, channel, sender)
    end
end)

_G.GrindkeepComm = {
    BroadcastAltAssignment = BroadcastAltAssignment,
    BroadcastAltRemoval = BroadcastAltRemoval,
    BroadcastLoot = BroadcastLoot,
    Export = Export,
    Import = Import,
    ShowImportDialog = ShowImportDialog,
    ExportLoot = ExportLoot,
    ImportLoot = ImportLoot,
    ShowLootImportDialog = ShowLootImportDialog,
    ShowTextWindow = ShowTextWindow,
    -- fuer die Tests
    _Base64Encode = Base64Encode,
    _Base64Decode = Base64Decode,
    _BuildLootPayload = BuildLootPayload,
    _ParseLootPayload = ParseLootPayload,
    _ReceiveChunk = ReceiveChunk,
    _HandleAddonMessage = HandleAddonMessage,
}

--[[
    Grindkeep - Loot.lua

    Erweiterung um Raid-/Gruppen-Loot-Tracking: erfasst automatisch, wer
    welches Item bekommen hat, damit spaeter nachgeschaut werden kann, ob
    ein bestimmtes Item schon vergeben wurde ("/gkeep loot check <Item>"
    oder das Such-Fenster unten).

    ================================================================
    ERKENNUNG: CHAT_MSG_LOOT statt Gildenbank-API
    ================================================================
    Anders als die Gildenbank-Transaktionen (Core.lua) kommt Loot nicht
    aus einer abfragbaren API, sondern nur aus dem Chat-Event
    CHAT_MSG_LOOT. Blizzard sendet dieses Event bei JEDER Loot-Vergabe
    an ALLE Mitglieder der Gruppe/des Raids (nicht nur an den
    Empfaenger) - genau das macht "wer hat Item X bekommen" ueberhaupt
    beobachtbar, unabhaengig von Beute-Modus (Meisterpluenderer,
    Gruppenbeute/Wuerfeln, Freie-Beute usw.). Einzige Ausnahme:
    "You receive loot: ..." (die eigene Vergabe) erscheint nur bei einem
    selbst - dafuer erkennt dieser Client seine eigene Vergabe trivial
    lokal.

    Um NICHT den deutschen/englischen Chat-Text hart zu verdrahten,
    werden Blizzards eigene lokalisierte Format-Strings (LOOT_ITEM,
    LOOT_ITEM_SELF, ...) in ein Lua-Suchmuster uebersetzt (siehe
    BuildPattern) - dieselbe, seit Jahren von Loot-/DKP-Addons genutzte
    Technik. EHRLICHER HINWEIS: Chat-Text-Parsing ist inhaerent etwas
    fragil (Formatierungen koennen sich mit Patches aendern); tritt hier
    ein Fehler auf, wird er im Chat ausgegeben statt das Addon abstuerzen
    zu lassen (siehe pcall im Event-Handler unten) - bitte den
    Fehlertext schicken, dann wird gezielt nachgebessert.

    ================================================================
    DEDUP
    ================================================================
    Ein Loot-Ereignis kann von diesem Client sowohl lokal (eigenes
    CHAT_MSG_LOOT) als auch per Gilden-Broadcast von einem anderen
    Grindkeep-Nutzer im selben Raid gemeldet werden. Vor dem Speichern
    wird deshalb in den zuletzt gespeicherten Eintraegen nach derselben
    Vergabe gesucht (gleiches Item, gleicher Empfaenger, gleiche Menge,
    hoechstens LOOT_DEDUP_SECONDS auseinander). Ein festes Minuten-Raster
    haette dieselbe Vergabe getrennt, sobald die beiden Meldungen auf
    verschiedene Seiten einer Minutengrenze fallen oder die Uhren der
    PCs etwas auseinandergehen.

    ================================================================
    STANDARDMAESSIG AUS
    ================================================================
    Die Erfassung ist ab 1.0 erst nach dem Einschalten in den Optionen
    aktiv und zaehlt nur in Schlachtzuegen (abschaltbar). Der Kern von
    Grindkeep ist die Gildenbank - Loot ist eine Zusatzfunktion.
]]

local DB = _G.GrindkeepDatabase
local L = _G.GrindkeepLocale

local function Print(msg)
    print("|cff2ecc71[Grindkeep]|r " .. tostring(msg))
end

-- ============================================================
-- Kompatibilitaets-Wrapper (dieselbe Absicherung wie in Core.lua/UI.lua:
-- GetItemInfo()/GetItemIcon() ohne C_Item-Praefix existieren in WoW
-- Forever laut In-Game-Test nicht mehr)
-- ============================================================
local function GetItemInfoCompat(itemID)
    if not itemID then return nil end
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemID)
    elseif GetItemInfo then
        return GetItemInfo(itemID)
    end
    return nil
end

local function GetItemIconCompat(itemID)
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID)
    elseif GetItemIcon then
        return GetItemIcon(itemID)
    end
    return nil
end

local function ItemIdFromLink(itemLink)
    if not itemLink then return nil end
    local id = itemLink:match("item:(%d+)")
    return id and tonumber(id)
end

-- ============================================================
-- Chat-Format-Strings -> Lua-Suchmuster
-- ============================================================
-- Wandelt einen Blizzard-Formatstring wie "%s receives loot: %s."
-- in ein Lua-Suchmuster mit Captures um: alle magischen Zeichen bis
-- auf %s/%d werden escaped, %s wird zu (.-) und %d zu (%d+). Dieselbe
-- Technik wird von etablierten Loot-/DKP-Addons genutzt, um Chat-
-- Nachrichten sprachunabhaengig auszuwerten statt den Text fest zu
-- verdrahten.
local function BuildPattern(fmt)
    if not fmt or fmt == "" then return nil end
    local out = fmt:gsub("%%%%", "\1") -- literales %% (falls vorhanden) zwischenparken
    out = out:gsub("([%^%$%(%)%.%[%]%*%+%-%?])", "%%%1")
    out = out:gsub("%%s", "(.-)")
    out = out:gsub("%%d", "(%%d+)")
    out = out:gsub("\1", "%%%%")
    return "^" .. out .. "$"
end

-- Reihenfolge wichtig: die spezifischeren "_MULTIPLE"-Varianten (mit
-- Stueckzahl) muessen VOR den einfachen Varianten geprueft werden.
local PAT_SELF_MULTIPLE  = BuildPattern(LOOT_ITEM_SELF_MULTIPLE)
local PAT_SELF_SINGLE    = BuildPattern(LOOT_ITEM_SELF)
local PAT_OTHER_MULTIPLE = BuildPattern(LOOT_ITEM_MULTIPLE)
local PAT_OTHER_SINGLE   = BuildPattern(LOOT_ITEM)
-- BEWUSST NICHT erfasst: LOOT_ITEM_PUSHED_SELF ("Ihr erhaltet
-- Gegenstand: ..."). Diese Meldung kommt auch fuer Questbelohnungen,
-- Haendlerkaeufe und Hergestelltes und wuerde sie als Raid-Beute
-- verbuchen.

-- Rueckgabe bei Treffer: recipient, itemLink, count - sonst nil.
local function TryMatch(message)
    if PAT_SELF_MULTIPLE then
        local itemLink, count = message:match(PAT_SELF_MULTIPLE)
        if itemLink then return UnitName("player"), itemLink, tonumber(count) or 1 end
    end
    if PAT_SELF_SINGLE then
        local itemLink = message:match(PAT_SELF_SINGLE)
        if itemLink then return UnitName("player"), itemLink, 1 end
    end
    if PAT_OTHER_MULTIPLE then
        local player, itemLink, count = message:match(PAT_OTHER_MULTIPLE)
        if player and itemLink then return player, itemLink, tonumber(count) or 1 end
    end
    if PAT_OTHER_SINGLE then
        local player, itemLink = message:match(PAT_OTHER_SINGLE)
        if player and itemLink then return player, itemLink, 1 end
    end
    return nil
end

-- ============================================================
-- Dedup (siehe Erklaerung im Datei-Kopfkommentar)
-- ============================================================
local LOOT_DEDUP_SECONDS = 180

-- Empfaenger vergleichen: "Name" und "Name-EigenerRealm" sind derselbe,
-- ein Bindestrich im Nachnamen bleibt Teil des Namens (siehe Names.lua).
local function SameRecipient(a, b)
    return (_G.GrindkeepNames.Same(a, b))
end

local function SameItem(a, b)
    if a.itemID and b.itemID then return a.itemID == b.itemID end
    return a.itemLink ~= nil and a.itemLink == b.itemLink
end

-- Gibt es dieselbe Vergabe schon unter den zuletzt gespeicherten?
-- isRemote = true: Meldung eines anderen Gildenmitglieds - gegen alles
-- pruefen. Eigene Beobachtung: nur gegen Meldungen anderer pruefen, denn
-- zwei eigene Chatmeldungen sind immer zwei echte Vergaben (z.B. dasselbe
-- Item von zwei Bossen kurz hintereinander).
local function ShouldAdd(record, isRemote)
    local g = DB.GetGuildData()
    if not g then return false end
    local ts = record.ts or DB.Now()
    local checked = 0
    for i = #g.loot, 1, -1 do
        local e = g.loot[i]
        if (isRemote or e.reportedBy ~= nil) and SameItem(e, record)
            and SameRecipient(e.recipient, record.recipient)
            and (e.count or 1) == (record.count or 1)
            and math.abs((e.ts or 0) - ts) <= LOOT_DEDUP_SECONDS then
            return false
        end
        checked = checked + 1
        if checked >= 300 then break end
    end
    return true
end

-- Qualitaet aus der Farbe des Itemlinks, falls der Client das Item noch
-- nicht kennt (dann liefert GetItemInfo nil). Deckt beide Linkformate ab:
-- "|cnIQ4:" (neuere Clients) und "|cffa335ee" (klassisch).
local QUALITY_BY_COLOR = {
    ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3,
    ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7,
}
local function QualityFromLink(itemLink)
    if type(itemLink) ~= "string" then return nil end
    local q = itemLink:match("|cnIQ(%d):")
    if q then return tonumber(q) end
    local hex = itemLink:match("|cff(%x%x%x%x%x%x)")
    return hex and QUALITY_BY_COLOR[hex:lower()] or nil
end

local function NameFromLink(itemLink)
    return type(itemLink) == "string" and itemLink:match("|h%[(.-)%]|h") or nil
end

local function CurrentLootMethod()
    if C_PartyInfo and C_PartyInfo.GetLootMethod then
        local ok, method = pcall(C_PartyInfo.GetLootMethod)
        if ok then return method end
    elseif GetLootMethod then
        local ok, method = pcall(GetLootMethod)
        if ok then return method end
    end
    return nil
end

-- ============================================================
-- Erfassung eigener/lokal beobachteter Vergaben
-- ============================================================
local function RecordLoot(recipient, itemLink, count)
    if not DB.GetSetting("lootTrackingEnabled") then return end
    if DB.GetSetting("lootRaidOnly") then
        if not (IsInRaid and IsInRaid()) then return end
    elseif not (IsInGroup and IsInGroup()) then
        return -- bewusst nur in Gruppe/Raid, kein Solo-Loot
    end

    local itemID = ItemIdFromLink(itemLink)
    local itemName, _, itemQuality = GetItemInfoCompat(itemID)
    itemQuality = itemQuality or QualityFromLink(itemLink)
    itemName = itemName or NameFromLink(itemLink)

    -- Mindest-Qualitaet: graues/weisses Trash-Loot soll den Log nicht
    -- zuspammen. Laesst sich die Qualitaet gar nicht bestimmen, wird im
    -- Zweifel erfasst, statt ein echtes Item zu verpassen.
    local minQuality = DB.GetSetting("lootMinQuality")
    if itemQuality and minQuality and itemQuality < minQuality then
        return
    end

    local record = {
        ts = DB.Now(),
        itemID = itemID,
        -- Den Link aus der Chatmeldung behalten: nur er enthaelt
        -- Schwierigkeitsgrad und Itemstufe des tatsaechlich gefallenen Items.
        itemLink = itemLink,
        itemName = itemName,
        itemQuality = itemQuality,
        count = count or 1,
        recipient = recipient,
        raidName = GetInstanceInfo and select(1, GetInstanceInfo()) or nil,
        lootMethod = CurrentLootMethod(),
    }

    if not ShouldAdd(record, false) then return end
    DB.AddLoot(record)

    if DB.GetSetting("scanChatMessages") then
        Print(string.format(L["LOOT_RECORDED_CHAT"], recipient, record.itemLink or "?",
            (record.count or 1) > 1 and ("x" .. record.count) or ""))
    end

    if _G.GrindkeepComm then _G.GrindkeepComm.BroadcastLoot(record) end
    if _G.GrindkeepLootUI then _G.GrindkeepLootUI.Refresh() end
end

-- Wird von Comm.lua bei eingehendem "LOOT:"-Broadcast eines vertrauten
-- Gildenmitglieds aufgerufen (Vertrauens-/Rangpruefung liegt dort).
local function OnRemoteLoot(record)
    if not DB.GetSetting("lootTrackingEnabled") then return end
    if not record then return end
    if not ShouldAdd(record, true) then return end
    record.itemName = record.itemName or NameFromLink(record.itemLink)
    DB.AddLoot(record)
    if _G.GrindkeepLootUI then _G.GrindkeepLootUI.Refresh() end
end

-- ============================================================
-- Event-Handling
-- ============================================================
local frame = CreateFrame("Frame")
frame:RegisterEvent("CHAT_MSG_LOOT")
frame:RegisterEvent("GET_ITEM_INFO_RECEIVED")

-- Per Gilden-Abgleich uebernommene Eintraege kommen ohne Namen und Link,
-- wenn der Client das Item noch nicht kannte - sobald die Item-Info
-- eintrifft, werden sie nachgetragen.
local function EnrichLoot(itemID)
    local g = DB.GetGuildData()
    if not g or not itemID then return end
    local checked = 0
    for i = #g.loot, 1, -1 do
        local e = g.loot[i]
        if e.itemID == itemID and (not e.itemLink or not e.itemName) then
            local name, link, quality = GetItemInfoCompat(e.itemString or itemID)
            e.itemName = e.itemName or name
            e.itemLink = e.itemLink or link
            e.itemQuality = e.itemQuality or quality
        end
        checked = checked + 1
        if checked >= 300 then break end
    end
end
local parseErrorShown = false
frame:SetScript("OnEvent", function(self, event, message, success)
    if event == "GET_ITEM_INFO_RECEIVED" then
        if success and DB.GetSetting("lootTrackingEnabled") then EnrichLoot(message) end
        return
    end
    if not DB.GetSetting("lootTrackingEnabled") then return end
    -- Neuere Clients koennen Chat-Inhalte in Instanzen als "geheime Werte"
    -- ausliefern, mit denen Addons nicht rechnen duerfen. Dann einfach
    -- nichts tun statt einen Fehler zu werfen.
    if issecretvalue and issecretvalue(message) then return end
    if type(message) ~= "string" then return end
    local ok, err = pcall(function()
        local recipient, itemLink, count = TryMatch(message)
        if recipient and itemLink then
            RecordLoot(recipient, itemLink, count)
        end
    end)
    if not ok and not parseErrorShown then
        parseErrorShown = true
        Print(string.format(L["LOOT_PARSE_ERROR"], tostring(err)))
    end
end)

-- ============================================================
-- Slash-Befehle (aufgerufen von Core.lua: /gkeep loot ...)
-- ============================================================
local function FormatLootLine(entry)
    return string.format("%s -> %s%s (%s)",
        entry.recipient or "?", entry.itemLink or entry.itemName or "?",
        (entry.count or 1) > 1 and ("x" .. entry.count) or "",
        entry.ts and date(L["DATE_FORMAT_SHORT"], entry.ts) or "?")
end

local function HandleSlash(sub, rest)
    rest = rest or {}
    if sub == "check" then
        local query = table.concat(rest, " ")
        if query == "" then
            Print(L["LOOT_NEED_ITEM"])
            return
        end
        -- Per Shift-Klick eingefuegter Itemlink: exakt nach der Item-ID suchen
        local linkedID = ItemIdFromLink(query)
        local results = linkedID and DB.GetLootForItem(linkedID) or DB.SearchLoot(query)
        if #results == 0 then
            Print(string.format(L["LOOT_NONE_FOUND"], query))
        else
            Print(string.format(L["LOOT_FOUND_COUNT"], #results))
            for i = 1, math.min(10, #results) do
                Print(FormatLootLine(results[i]))
            end
        end
    elseif sub == "recent" then
        local n = tonumber(rest[1]) or 15
        local results = DB.GetRecentLoot(n)
        if #results == 0 then
            Print(L["LOOT_NONE_RECORDED"])
        else
            for _, entry in ipairs(results) do
                Print(FormatLootLine(entry))
            end
        end
    elseif sub == "ui" then
        if _G.GrindkeepLootUI then _G.GrindkeepLootUI.Toggle() end
    elseif sub == "stats" then
        if _G.GrindkeepLootUI then _G.GrindkeepLootUI.ShowStats() end
    elseif sub == "export" then
        if _G.GrindkeepComm then _G.GrindkeepComm.ExportLoot() end
    elseif sub == "import" then
        if _G.GrindkeepComm then
            if rest[1] then
                -- Direkter Weg mit String als Argument: siehe Comm.lua -
                -- funktioniert nur zuverlaessig fuer kurze Strings (Chat-
                -- Eingabezeilenlimit).
                _G.GrindkeepComm.ImportLoot(rest[1])
            else
                _G.GrindkeepComm.ShowLootImportDialog()
            end
        end
    else
        Print(L["LOOT_HELP"])
    end
end

_G.GrindkeepLoot = {
    OnRemoteLoot = OnRemoteLoot,
    HandleSlash = HandleSlash,
}

-- ============================================================
-- Eigenstaendiges Such-/Uebersichtsfenster
-- ============================================================
-- Bewusst ein zweites, einfacheres Fenster statt eines weiteren Tabs im
-- ohnehin schon umfangreichen UI.lua (ScrollBox/Kontextmenue-Logik dort
-- nicht anfassen muessen) - UI.lua bindet nur einen kleinen "Loot"-
-- Knopf ein, der dieses Fenster oeffnet.
--
-- Optische Anpassung (siehe UI.lua-Kopfkommentar fuer den vollen
-- Hintergrund - hier nur die Kurzfassung): natives dunkles Dialog-
-- Backdrop statt flacher Eigenbau-Farbflaeche, erweiterte Statusfarben-
-- Palette, Wasserzeichen, Minimieren-Knopf. Farbpalette + Backdrop-
-- Helfer bewusst hier lokal dupliziert (dieselben Werte/Technik wie in
-- UI.lua), damit Loot.lua auch dann eigenstaendig funktioniert, wenn
-- UI.lua aus irgendeinem Grund nicht laedt.
local C = {
    bg      = { 18 / 255, 18 / 255, 22 / 255, 0.95 },
    panelBg = { 24 / 255, 24 / 255, 29 / 255, 0.95 },
    border  = { 0x2a / 255, 0x2d / 255, 0x34 / 255, 1 },
    warning = { 0xe6 / 255, 0x7e / 255, 0x22 / 255, 1 },
    textDim = { 0.55, 0.55, 0.6, 1 },
}
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}
local function Backdrop(frameObj, bgColor, borderColor)
    frameObj:SetBackdrop(BACKDROP)
    frameObj:SetBackdropColor(unpack(bgColor))
    frameObj:SetBackdropBorderColor(unpack(borderColor))
end

-- Siehe UI.lua: dasselbe native Blizzard-Backdrop mit demselben
-- Fallback, falls der Global fehlen sollte.
local function ApplyWindowBackdrop(frameObj)
    if _G.BACKDROP_DARK_DIALOG_32_32 then
        frameObj:SetBackdrop(_G.BACKDROP_DARK_DIALOG_32_32)
    else
        frameObj:SetBackdrop(BACKDROP)
        frameObj:SetBackdropColor(unpack(C.bg))
        frameObj:SetBackdropBorderColor(unpack(C.border))
    end
end

local function GetAddonVersion()
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not getter then return "?" end
    local ok, version = pcall(getter, "Grindkeep", "Version")
    if ok and version then return version end
    return "?"
end

local LOOT_EDGE = 13
local LOOT_WATERMARK_HEIGHT = 14
local LOOT_EXPANDED_HEIGHT = 380
local lootIsMinimized = false

local LootFrame = CreateFrame("Frame", "GrindkeepLootFrame", UIParent, "BackdropTemplate")
tinsert(UISpecialFrames, "GrindkeepLootFrame") -- mit Escape schliessbar
LootFrame:SetSize(420, LOOT_EXPANDED_HEIGHT)
LootFrame:SetPoint("CENTER")
LootFrame:SetFrameStrata("HIGH")
LootFrame:SetMovable(true)
LootFrame:EnableMouse(true)
LootFrame:RegisterForDrag("LeftButton")
LootFrame:SetScript("OnDragStart", LootFrame.StartMoving)
LootFrame:SetScript("OnDragStop", LootFrame.StopMovingOrSizing)
ApplyWindowBackdrop(LootFrame)
LootFrame:Hide()

local lootHeader = CreateFrame("Frame", nil, LootFrame, "BackdropTemplate")
lootHeader:SetHeight(36)
lootHeader:SetPoint("TOPLEFT", LOOT_EDGE, -LOOT_EDGE)
lootHeader:SetPoint("TOPRIGHT", -LOOT_EDGE, -LOOT_EDGE)
Backdrop(lootHeader, C.panelBg, C.border)
lootHeader:EnableMouse(true)
lootHeader:RegisterForDrag("LeftButton")
lootHeader:SetScript("OnDragStart", function() LootFrame:StartMoving() end)
lootHeader:SetScript("OnDragStop", function() LootFrame:StopMovingOrSizing() end)

local lootTitle = lootHeader:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
lootTitle:SetPoint("LEFT", 10, 0)
lootTitle:SetText(L["LOOT_WINDOW_TITLE"])

local lootCloseBtn = CreateFrame("Button", nil, lootHeader, "UIPanelCloseButton")
lootCloseBtn:SetPoint("RIGHT", -4, 0)
lootCloseBtn:SetScript("OnClick", function() LootFrame:Hide() end)

-- Vorwaertsdeklaration: der Minimieren-Knopf muss den Rest des Fensters
-- ein-/ausblenden koennen, das erst weiter unten entsteht.
local lootBody

local lootMinimizeBtn = CreateFrame("Button", nil, lootHeader)
lootMinimizeBtn:SetSize(20, 20)
lootMinimizeBtn:SetPoint("RIGHT", lootCloseBtn, "LEFT", -2, 0)
local lootMinimizeLabel = lootMinimizeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
lootMinimizeLabel:SetAllPoints()
lootMinimizeLabel:SetText("-")
lootMinimizeBtn:SetScript("OnClick", function()
    lootIsMinimized = not lootIsMinimized
    if lootIsMinimized then
        LootFrame:SetHeight(lootHeader:GetHeight() + LOOT_EDGE * 2)
        lootBody:Hide()
        lootMinimizeLabel:SetText("+")
    else
        LootFrame:SetHeight(LOOT_EXPANDED_HEIGHT)
        lootBody:Show()
        lootMinimizeLabel:SetText("-")
    end
end)

-- Wasserzeichen unten links.
local lootWatermark = LootFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
lootWatermark:SetPoint("BOTTOMLEFT", LOOT_EDGE + 4, LOOT_EDGE - 8)
lootWatermark:SetText("Grindkeep v" .. GetAddonVersion())

-- lootBody buendelt Suchfeld + Hinweise + Ergebnisliste, damit der
-- Minimieren-Knopf oben nur EIN Frame ein-/ausblenden muss.
lootBody = CreateFrame("Frame", nil, LootFrame)
lootBody:SetPoint("TOPLEFT", lootHeader, "BOTTOMLEFT", 0, 0)
lootBody:SetPoint("BOTTOMRIGHT", LootFrame, "BOTTOMRIGHT", -LOOT_EDGE, LOOT_EDGE + LOOT_WATERMARK_HEIGHT)
lootBody:SetPoint("TOPRIGHT", lootHeader, "BOTTOMRIGHT", 0, 0)

local lootSearchBox = CreateFrame("EditBox", nil, lootBody, "InputBoxTemplate")
lootSearchBox:SetSize(290, 20)
lootSearchBox:SetPoint("TOPLEFT", lootBody, "TOPLEFT", 1, -10)
lootSearchBox:SetAutoFocus(false)
lootSearchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

-- Vorwaertsdeklaration: der Umschalt-Knopf braucht RefreshLootView, das
-- erst weiter unten definiert wird (nachdem sowohl Such- als auch
-- Statistik-Ansicht existieren).
local lootStatsMode = false
local RefreshLootView

local lootModeBtn = CreateFrame("Button", nil, lootBody, "UIPanelButtonTemplate")
lootModeBtn:SetSize(84, 20)
lootModeBtn:SetPoint("LEFT", lootSearchBox, "RIGHT", 6, 0)
lootModeBtn:SetText(L["LOOT_MODE_STATS_BUTTON"])

local lootHint = lootBody:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
lootHint:SetPoint("TOPLEFT", lootSearchBox, "BOTTOMLEFT", 1, -4)
lootHint:SetText(L["LOOT_SEARCH_HINT"])

-- Warnhinweis, falls die automatische Erfassung in den Optionen
-- deaktiviert ist - sonst wundert man sich stillschweigend, warum
-- nichts Neues auftaucht. Nutzt die neue Warnfarbe (siehe UI.lua-
-- Kommentar zur erweiterten Statusfarben-Palette).
local lootDisabledHint = lootBody:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
lootDisabledHint:SetPoint("TOPLEFT", lootHint, "BOTTOMLEFT", 0, -4)
lootDisabledHint:SetTextColor(unpack(C.warning))
lootDisabledHint:SetText(L["LOOT_DISABLED_HINT"])
lootDisabledHint:Hide()

local lootResultBox = CreateFrame("Frame", nil, lootBody, "WowScrollBoxList")
-- Verankert an lootDisabledHint statt lootHint: dessen Position bleibt
-- gleich, ob er gerade sichtbar ist oder nicht (Hide() aendert nur die
-- Sichtbarkeit, nicht die Anker) - so bekommt die Ergebnisliste in
-- jedem Fall genug Platz unterhalb des (ggf. unsichtbaren) Warnhinweises.
lootResultBox:SetPoint("TOPLEFT", lootDisabledHint, "BOTTOMLEFT", -1, -8)
lootResultBox:SetPoint("BOTTOMRIGHT", lootBody, "BOTTOMRIGHT", -26, 0)

local lootResultBar = CreateFrame("EventFrame", nil, lootBody, "MinimalScrollBar")
lootResultBar:SetPoint("TOPLEFT", lootResultBox, "TOPRIGHT", 4, 0)
lootResultBar:SetPoint("BOTTOMLEFT", lootResultBox, "BOTTOMRIGHT", 4, 0)

local function InitLootRow(button, entry)
    if not button.initialized then
        button.initialized = true

        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(24, 24)
        button.icon:SetPoint("LEFT", 4, 2)

        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.text:SetPoint("LEFT", button.icon, "RIGHT", 8, 6)
        button.text:SetPoint("RIGHT", -8, 6)
        button.text:SetJustifyH("LEFT")

        button.sub = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        button.sub:SetPoint("LEFT", button.icon, "RIGHT", 8, -8)

        button:SetScript("OnEnter", function(self)
            if self.itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetHyperlink(self.itemLink)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    local icon = (entry.itemID and GetItemIconCompat(entry.itemID)) or 134400
    button.icon:SetTexture(icon)
    button.itemLink = entry.itemLink

    local label = entry.itemLink or entry.itemName or L["LOOT_UNKNOWN_ITEM"]
    button.text:SetText(string.format("%s%s -> |cffffffff%s|r", label,
        (entry.count or 1) > 1 and ("x" .. entry.count) or "", entry.recipient or "?"))

    local when = entry.ts and date(L["DATE_FORMAT"], entry.ts) or "?"
    local sub = when .. (entry.raidName and (" - " .. entry.raidName) or "")
    if entry.reportedBy then
        -- Kennzeichnet Eintraege, die per Gilden-Broadcast von einem
        -- anderen Grindkeep-Client uebernommen wurden (siehe Comm.lua),
        -- statt selbst per CHAT_MSG_LOOT beobachtet worden zu sein.
        sub = sub .. string.format(L["LOOT_VIA_SUFFIX"], entry.reportedBy)
    end
    button.sub:SetText(sub)
end

local lootView = CreateScrollBoxListLinearView()
lootView:SetElementExtent(32)
lootView:SetElementFactory(function(factory, elementData)
    factory("Button", InitLootRow)
end)
ScrollUtil.InitScrollBoxListWithScrollBar(lootResultBox, lootResultBar, lootView)

-- ============================================================
-- Statistik-Ansicht (auf Wunsch ergaenzt): wer hat insgesamt/zuletzt wie
-- viel Loot bekommen - fuer Verteilungsentscheidungen (Loot-Rat/Prio-
-- Liste), ohne die komplette Rohliste durchscrollen zu muessen. Teilt sich
-- denselben lootBody-Bereich mit der Suche oben (nur eines von beiden ist
-- je Modus sichtbar), damit das Fenster nicht groesser werden muss.
-- ============================================================
local lootStatsSortMode = "count" -- entspricht DB.GetLootPlayerStats()'s sortBy
local RefreshLootStats -- Vorwaertsdeklaration fuer die Sortier-Knopf-Handler

local lootStatsSortBar = CreateFrame("Frame", nil, lootBody)
lootStatsSortBar:SetHeight(20)
lootStatsSortBar:SetPoint("TOPLEFT", lootBody, "TOPLEFT", 1, -10)
lootStatsSortBar:SetPoint("TOPRIGHT", lootBody, "TOPRIGHT", -1, -10)
lootStatsSortBar:Hide()

local function CreateStatsSortButton(labelText, sortKey, xOffset)
    local btn = CreateFrame("Button", nil, lootStatsSortBar)
    btn:SetSize(78, 20)
    btn:SetPoint("LEFT", xOffset, 0)
    local label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetAllPoints()
    label:SetText(labelText)
    btn.label = label
    btn:SetScript("OnClick", function()
        lootStatsSortMode = sortKey
        RefreshLootStats()
    end)
    return btn
end

local lootStatsSortCount = CreateStatsSortButton(L["LOOT_STATS_SORT_COUNT"], "count", 0)
local lootStatsSortEntries = CreateStatsSortButton(L["LOOT_STATS_SORT_ENTRIES"], "entries", 84)
local lootStatsSortRecent = CreateStatsSortButton(L["LOOT_STATS_SORT_RECENT"], "activity", 168)

local lootStatsBox = CreateFrame("Frame", nil, lootBody, "WowScrollBoxList")
lootStatsBox:SetPoint("TOPLEFT", lootStatsSortBar, "BOTTOMLEFT", -1, -8)
lootStatsBox:SetPoint("BOTTOMRIGHT", lootBody, "BOTTOMRIGHT", -26, 0)
lootStatsBox:Hide()

local lootStatsBar = CreateFrame("EventFrame", nil, lootBody, "MinimalScrollBar")
lootStatsBar:SetPoint("TOPLEFT", lootStatsBox, "TOPRIGHT", 4, 0)
lootStatsBar:SetPoint("BOTTOMLEFT", lootStatsBox, "BOTTOMRIGHT", 4, 0)
lootStatsBar:Hide()

local function InitStatsRow(button, entry)
    if not button.initialized then
        button.initialized = true

        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.text:SetPoint("LEFT", 4, 6)
        button.text:SetPoint("RIGHT", -8, 6)
        button.text:SetJustifyH("LEFT")

        button.sub = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        button.sub:SetPoint("LEFT", 4, -8)
    end

    button.text:SetText(string.format(L["LOOT_STATS_ROW_MAIN"], entry.name, entry.totalCount))
    local lastStr = entry.lastTs and entry.lastTs > 0 and date(L["DATE_FORMAT_DAY"], entry.lastTs) or "?"
    button.sub:SetText(string.format(L["LOOT_STATS_ROW_SUB"], entry.entries, lastStr))
end

local lootStatsView = CreateScrollBoxListLinearView()
lootStatsView:SetElementExtent(32)
lootStatsView:SetElementFactory(function(factory, elementData)
    factory("Button", InitStatsRow)
end)
ScrollUtil.InitScrollBoxListWithScrollBar(lootStatsBox, lootStatsBar, lootStatsView)

function RefreshLootStats()
    local stats = DB.GetLootPlayerStats(lootStatsSortMode)
    lootStatsBox:SetDataProvider(CreateDataProvider(stats))
end

local function RefreshLootResults()
    if DB.GetSetting("lootTrackingEnabled") then
        lootDisabledHint:Hide()
    else
        lootDisabledHint:Show()
    end

    local query = lootSearchBox:GetText()
    local results
    if query and query ~= "" then
        results = DB.SearchLoot(query)
    else
        results = DB.GetRecentLoot(50)
    end
    lootResultBox:SetDataProvider(CreateDataProvider(results))
end

function RefreshLootView()
    if lootStatsMode then
        RefreshLootStats()
    else
        RefreshLootResults()
    end
end

-- Blendet zwischen Such-/Browse-Ansicht (Standard) und Statistik-Ansicht
-- um - beide teilen sich denselben Platz im Fenster (siehe Kommentar
-- oben bei lootStatsSortBar), daher immer paarweise ein-/ausblenden.
local function SetLootStatsMode(enabled)
    lootStatsMode = enabled
    if enabled then
        lootSearchBox:Hide()
        lootHint:Hide()
        lootDisabledHint:Hide()
        lootResultBox:Hide()
        lootResultBar:Hide()

        lootStatsSortBar:Show()
        lootStatsBox:Show()
        lootStatsBar:Show()
        lootModeBtn:SetText(L["LOOT_MODE_SEARCH_BUTTON"])
    else
        lootStatsSortBar:Hide()
        lootStatsBox:Hide()
        lootStatsBar:Hide()

        lootSearchBox:Show()
        lootHint:Show()
        lootResultBox:Show()
        lootResultBar:Show()
        lootModeBtn:SetText(L["LOOT_MODE_STATS_BUTTON"])
    end
    RefreshLootView()
end

lootModeBtn:SetScript("OnClick", function() SetLootStatsMode(not lootStatsMode) end)

lootSearchBox:SetScript("OnTextChanged", RefreshLootResults)
LootFrame:SetScript("OnShow", RefreshLootView)

-- Seit 1.1 ist Loot eine Seite im Hauptfenster (nur sichtbar, wenn die
-- Loot-Erfassung eingeschaltet ist).
local lootEmbedded = false

local function ShowLootFrame()
    if lootEmbedded and _G.GrindkeepUI and _G.GrindkeepUI.ShowTab then
        _G.GrindkeepUI.ShowTab("loot")
    else
        LootFrame:Show()
    end
end

local function ToggleLootUI()
    if lootEmbedded and _G.GrindkeepUI and _G.GrindkeepUI.ToggleTab then
        _G.GrindkeepUI.ToggleTab("loot")
    elseif LootFrame:IsShown() then
        LootFrame:Hide()
    else
        LootFrame:Show()
    end
end

local function EmbedLoot(parent)
    if lootEmbedded then return LootFrame end
    lootEmbedded = true
    _G.GrindkeepStyle.EmbedFrame(LootFrame, parent)
    lootHeader:Hide()
    lootWatermark:Hide()
    lootIsMinimized = false
    lootBody:ClearAllPoints()
    lootBody:SetPoint("TOPLEFT", LootFrame, "TOPLEFT", 0, 0)
    lootBody:SetPoint("BOTTOMRIGHT", LootFrame, "BOTTOMRIGHT", 0, 0)
    lootBody:Show()
    return LootFrame
end

_G.GrindkeepLootUI = {
    Frame = LootFrame,
    Toggle = ToggleLootUI,
    Embed = EmbedLoot,
    ShowStats = function()
        ShowLootFrame()
        SetLootStatsMode(true)
    end,
    Refresh = function()
        if LootFrame:IsShown() then RefreshLootView() end
    end,
}

if _G.GrindkeepStyle then
    _G.GrindkeepStyle.RegisterAndApply(LootFrame)
end

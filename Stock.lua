--[[
    Grindkeep - Stock.lua

    Bestandsfenster: zeigt, was aktuell in den Faechern der Gildenbank
    liegt, und stellt es den hinterlegten Mindestbestaenden gegenueber.

    Abgrenzung zum Hauptfenster (UI.lua): dort geht es um PERSONEN - wer
    hat wie viel eingezahlt oder entnommen. Hier geht es um den
    BESTAND - was ist da und was fehlt. Zwei verschiedene Fragen, zwei
    Fenster; sie in eines zu quetschen haette beides unuebersichtlich
    gemacht (dieselbe Ueberlegung wie beim Loot-Fenster in Loot.lua).

    Datenquelle ist ausschliesslich Database.lua
    (GetInventoryList/GetStockList) - dieses Modul liest und zeichnet
    nur, es scannt nichts selbst. Der Scan liegt in Core.lua.

    Farbpalette und Backdrop-Helfer sind - wie in Loot.lua - bewusst
    lokal dupliziert, damit das Fenster auch dann funktioniert, wenn
    UI.lua aus irgendeinem Grund nicht geladen wird.
]]

local DB = _G.GrindkeepDatabase
local L = _G.GrindkeepLocale

local C = {
    bg      = { 18 / 255, 18 / 255, 22 / 255, 0.95 },
    panelBg = { 24 / 255, 24 / 255, 29 / 255, 0.95 },
    border  = { 0x2a / 255, 0x2d / 255, 0x34 / 255, 1 },
    good    = { 0x2e / 255, 0xcc / 255, 0x71 / 255, 1 },
    warning = { 0xe6 / 255, 0x7e / 255, 0x22 / 255, 1 },
    bad     = { 0xe7 / 255, 0x4c / 255, 0x3c / 255, 1 },
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

local function ApplyWindowBackdrop(frameObj)
    if _G.BACKDROP_DARK_DIALOG_32_32 then
        frameObj:SetBackdrop(_G.BACKDROP_DARK_DIALOG_32_32)
    else
        frameObj:SetBackdrop(BACKDROP)
        frameObj:SetBackdropColor(unpack(C.bg))
        frameObj:SetBackdropBorderColor(unpack(C.border))
    end
end

local function GetItemIconCompat(itemID)
    if C_Item and C_Item.GetItemIconByID then
        local ok, icon = pcall(C_Item.GetItemIconByID, itemID)
        if ok and icon then return icon end
    end
    if GetItemIcon then
        local ok, icon = pcall(GetItemIcon, itemID)
        if ok and icon then return icon end
    end
    return nil
end

local function GetAddonVersion()
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not getter then return "?" end
    local ok, version = pcall(getter, "Grindkeep", "Version")
    if ok and version then return version end
    return "?"
end

local EDGE = 13
local WATERMARK_HEIGHT = 14

-- ============================================================
-- Fenster
-- ============================================================
local StockFrame = CreateFrame("Frame", "GrindkeepStockFrame", UIParent, "BackdropTemplate")
StockFrame:SetSize(460, 420)
StockFrame:SetPoint("CENTER", 120, 0)
StockFrame:SetFrameStrata("HIGH")
StockFrame:SetMovable(true)
StockFrame:EnableMouse(true)
StockFrame:RegisterForDrag("LeftButton")
StockFrame:SetScript("OnDragStart", StockFrame.StartMoving)
StockFrame:SetScript("OnDragStop", StockFrame.StopMovingOrSizing)
ApplyWindowBackdrop(StockFrame)
StockFrame:Hide()
tinsert(UISpecialFrames, "GrindkeepStockFrame") -- mit Escape schliessbar

-- Groesse wie beim Hauptfenster per Shift+Ziehen aenderbar
StockFrame:SetResizable(true)
if StockFrame.SetResizeBounds then
    StockFrame:SetResizeBounds(380, 260, 1200, 900)
else
    if StockFrame.SetMinResize then StockFrame:SetMinResize(380, 260) end
    if StockFrame.SetMaxResize then StockFrame:SetMaxResize(1200, 900) end
end
StockFrame:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and IsShiftKeyDown() then self:StartSizing("BOTTOMRIGHT") end
end)
StockFrame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

local header = CreateFrame("Frame", nil, StockFrame, "BackdropTemplate")
header:SetHeight(36)
header:SetPoint("TOPLEFT", EDGE, -EDGE)
header:SetPoint("TOPRIGHT", -EDGE, -EDGE)
Backdrop(header, C.panelBg, C.border)
header:EnableMouse(true)
header:RegisterForDrag("LeftButton")
header:SetScript("OnDragStart", function()
    if IsShiftKeyDown() then StockFrame:StartSizing("BOTTOMRIGHT") else StockFrame:StartMoving() end
end)
header:SetScript("OnDragStop", function() StockFrame:StopMovingOrSizing() end)

local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("LEFT", 10, 0)
title:SetText(L["STOCK_WINDOW_TITLE"])

local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
closeBtn:SetPoint("RIGHT", -4, 0)
closeBtn:SetScript("OnClick", function() StockFrame:Hide() end)

local scannedAtText = header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
scannedAtText:SetPoint("RIGHT", closeBtn, "LEFT", -8, 0)

local body = CreateFrame("Frame", nil, StockFrame)
body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
body:SetPoint("BOTTOMRIGHT", StockFrame, "BOTTOMRIGHT", -EDGE, EDGE + WATERMARK_HEIGHT)

local watermark = StockFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
watermark:SetPoint("BOTTOMLEFT", EDGE + 2, EDGE - 2)
watermark:SetText("Grindkeep v" .. GetAddonVersion())
watermark:SetTextColor(unpack(C.textDim))

-- ---------- Kopfzeile des Inhalts: Filter + Neu einlesen ----------
local onlyMissing = false
local Refresh -- Vorwaertsdeklaration

local filterBtn = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
filterBtn:SetSize(130, 20)
filterBtn:SetPoint("TOPLEFT", body, "TOPLEFT", 1, -4)
filterBtn:SetText(L["STOCK_FILTER_ALL"])
filterBtn:SetScript("OnClick", function(self)
    onlyMissing = not onlyMissing
    self:SetText(onlyMissing and L["STOCK_FILTER_MISSING"] or L["STOCK_FILTER_ALL"])
    Refresh()
end)

local rescanBtn = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
rescanBtn:SetSize(110, 20)
rescanBtn:SetPoint("LEFT", filterBtn, "RIGHT", 6, 0)
rescanBtn:SetText(L["STOCK_RESCAN_BUTTON"])
rescanBtn:SetScript("OnClick", function()
    if _G.GrindkeepScanner and _G.GrindkeepScanner.StartInventoryScan then
        _G.GrindkeepScanner.StartInventoryScan()
    end
end)

local hint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
hint:SetPoint("TOPLEFT", filterBtn, "BOTTOMLEFT", 1, -6)
hint:SetPoint("RIGHT", body, "RIGHT", -8, 0)
hint:SetJustifyH("LEFT")
hint:SetText(L["STOCK_HINT"])

-- ---------- Export (allgemeines Export-Fenster, Export.lua) ----------
local exportBtn = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
exportBtn:SetSize(90, 20)
exportBtn:SetPoint("TOPRIGHT", body, "TOPRIGHT", -2, -4)
exportBtn:SetText(L["EXPORT_BUTTON"])
exportBtn:SetScript("OnClick", function()
    if _G.GrindkeepExportUI then _G.GrindkeepExportUI.Show("stock") end
end)

-- ---------- Quelle: Gildenbank, Lager-Twinks oder beides (seit 1.3) ----------
local source = "all"
local sourceButtons = {}

local sourceLabel = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
sourceLabel:SetPoint("TOPLEFT", hint, "BOTTOMLEFT", 0, -10)
sourceLabel:SetText(L["STOCK_SOURCE_LABEL"])
sourceLabel:SetTextColor(unpack(C.textDim))

local function AccentColor()
    local T = _G.GrindkeepTheme
    return T and T.Color("accent") or C.good
end

local function HighlightSources()
    local T = _G.GrindkeepTheme
    for key, b in pairs(sourceButtons) do
        if key == source then
            b.label:SetTextColor(unpack(AccentColor()))
        else
            b.label:SetTextColor(unpack(T and T.Color("textMid") or C.textDim))
        end
    end
end

local prevSource = sourceLabel
for _, e in ipairs({
    { key = "all",     label = L["STOCK_SOURCE_ALL"] },
    { key = "bank",    label = L["STOCK_SOURCE_BANK"] },
    { key = "storage", label = L["STOCK_SOURCE_STORAGE"] },
}) do
    local b = CreateFrame("Button", nil, body)
    b:SetHeight(18)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER")
    b.label:SetText(e.label)
    b:SetWidth(math.max(40, (tonumber(b.label:GetStringWidth()) or 40) + 16))
    b:SetPoint("LEFT", prevSource, "RIGHT", prevSource == sourceLabel and 8 or 2, 0)
    b:SetScript("OnClick", function()
        source = e.key
        HighlightSources()
        Refresh()
    end)
    sourceButtons[e.key] = b
    prevSource = b
end

-- Haken: dieser Charakter ist ein Lager-Twink
local storageCheck = CreateFrame("CheckButton", nil, body, "UICheckButtonTemplate")
storageCheck:SetSize(22, 22)
storageCheck:SetPoint("LEFT", prevSource, "RIGHT", 18, 0)
if storageCheck.Text then
    storageCheck.Text:SetText(L["STOCK_STORAGE_CHECK"])
    storageCheck.Text:SetFontObject("GameFontHighlightSmall")
end
storageCheck:SetScript("OnClick", function(self)
    if _G.GrindkeepStorage then _G.GrindkeepStorage.SetCurrent(self:GetChecked() and true or false) end
    Refresh()
end)
storageCheck:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(L["STOCK_STORAGE_CHECK_TOOLTIP"], 1, 1, 1, 1, true)
    GameTooltip:Show()
end)
storageCheck:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Welche Lager-Twinks gibt es, und wie aktuell sind sie?
local storageInfo = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
storageInfo:SetPoint("TOPLEFT", sourceLabel, "BOTTOMLEFT", 0, -8)
storageInfo:SetPoint("RIGHT", body, "RIGHT", -8, 0)
storageInfo:SetJustifyH("LEFT")
storageInfo:SetWordWrap(true)

-- ---------- Liste ----------
local listBox = CreateFrame("Frame", nil, body, "WowScrollBoxList")
listBox:SetPoint("TOPLEFT", storageInfo, "BOTTOMLEFT", -1, -8)
listBox:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -26, 0)

local listBar = CreateFrame("EventFrame", nil, body, "MinimalScrollBar")
listBar:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 4, 0)
listBar:SetPoint("BOTTOMLEFT", listBox, "BOTTOMRIGHT", 4, 0)

local function InitRow(button, entry)
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
        button.sub:SetPoint("RIGHT", -8, -8)
        button.sub:SetJustifyH("LEFT")

        button:SetScript("OnEnter", function(self)
            if self.itemLink or self.sources then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                if self.itemLink then
                    pcall(GameTooltip.SetHyperlink, GameTooltip, self.itemLink)
                else
                    GameTooltip:SetText(self.itemName or "?")
                end
                if self.sources and #self.sources > 0 then
                    GameTooltip:AddLine(" ")
                    GameTooltip:AddLine(L["STOCK_WHERE"], 1, 0.82, 0)
                    for _, s in ipairs(self.sources) do
                        GameTooltip:AddDoubleLine(s.name, tostring(s.count), 1, 1, 1, 1, 1, 1)
                    end
                end
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    button.itemLink = entry.itemLink
    button.itemName = entry.itemName
    button.sources = entry.sources
    button.icon:SetTexture((entry.itemID and GetItemIconCompat(entry.itemID)) or 134400)

    local label = entry.itemLink or entry.itemName or ("Item " .. tostring(entry.itemID))
    button.text:SetText(string.format("|cffffffff%d|r x %s", entry.have or entry.count or 0, label))

    if entry.required then
        if (entry.missing or 0) > 0 then
            button.sub:SetTextColor(unpack(C.bad))
            button.sub:SetText(string.format(L["STOCK_ROW_MISSING"], entry.required, entry.missing))
        else
            button.sub:SetTextColor(unpack(C.good))
            button.sub:SetText(string.format(L["STOCK_ROW_OK"], entry.required))
        end
    else
        button.sub:SetTextColor(unpack(C.textDim))
        button.sub:SetText(L["STOCK_ROW_NO_MINIMUM"])
    end
    -- Verteilung auf Bank und Twinks kurz dazuschreiben
    if entry.whereText then
        button.sub:SetText(button.sub:GetText() .. "  -  " .. entry.whereText)
    end
end

local view = CreateScrollBoxListLinearView()
view:SetElementExtent(32)
view:SetElementFactory(function(factory, elementData)
    factory("Button", function(button) InitRow(button, elementData) end)
end)
ScrollUtil.InitScrollBoxListWithScrollBar(listBox, listBar, view)

local emptyText = body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
emptyText:SetPoint("TOP", listBox, "TOP", 0, -30)
emptyText:Hide()

-- ============================================================
-- Daten zusammenstellen
--
-- Angezeigt wird der Bestand, angereichert um den Mindestbestand -
-- plus die Faelle, fuer die ein Mindestbestand hinterlegt ist, das Item
-- aber GAR NICHT (mehr) in der Bank liegt. Letztere sind die
-- wichtigsten Zeilen ueberhaupt und duerfen deshalb nicht fehlen, nur
-- weil sie im Bestand nicht vorkommen.
-- ============================================================
local function SourceName(name)
    if name == "@bank" then return L["STOCK_SOURCE_BANK"] end
    return name
end

-- Kurzer Text "Gildenbank 20, Beltog 15" (nur wenn es mehr als eine Quelle gibt)
local function WhereText(sources)
    if not sources or #sources < 2 then return nil end
    local parts = {}
    for _, s in ipairs(sources) do table.insert(parts, SourceName(s.name) .. " " .. s.count) end
    return table.concat(parts, ", ")
end

local function LocalizedSources(sources)
    local out = {}
    for _, s in ipairs(sources or {}) do table.insert(out, { name = SourceName(s.name), count = s.count }) end
    return out
end

local function CountFor(row)
    if source == "bank" then return row.bankCount or row.haveBank or 0 end
    if source == "storage" then return row.storageCount or row.haveStorage or 0 end
    return row.count or row.have or 0
end

local function BuildRows()
    local rows = {}
    local byId = {}

    local combined = DB.GetCombinedInventory and DB.GetCombinedInventory(source) or {}
    for _, item in ipairs(combined) do
        local row = {
            itemID = item.itemID,
            itemName = item.itemName,
            itemLink = item.itemLink,
            have = CountFor(item),
            sources = LocalizedSources(item.sources),
        }
        row.whereText = source == "all" and WhereText(item.sources) or nil
        byId[item.itemID] = row
        table.insert(rows, row)
    end

    -- Mindestbestaende einmischen (Soll/Fehlt beziehen sich immer auf
    -- Gildenbank + Lager-Twinks zusammen)
    for _, entry in ipairs(DB.GetStockList(false)) do
        local row = byId[entry.itemID]
        if not row then
            row = {
                itemID = entry.itemID,
                itemName = entry.itemName,
                itemLink = entry.itemLink,
                have = CountFor(entry),
                sources = {},
            }
            byId[entry.itemID] = row
            table.insert(rows, row)
        end
        row.required = entry.required
        row.missing = entry.missing
    end

    if onlyMissing then
        for i = #rows, 1, -1 do
            if not rows[i].required or (rows[i].missing or 0) <= 0 then table.remove(rows, i) end
        end
    end

    -- Fehlendes zuerst, dann nach Menge
    table.sort(rows, function(a, b)
        local am, bm = a.missing or 0, b.missing or 0
        if am ~= bm then return am > bm end
        if (a.have or 0) ~= (b.have or 0) then return (a.have or 0) > (b.have or 0) end
        return (a.itemName or "") < (b.itemName or "")
    end)
    return rows
end

local function RefreshStorageInfo()
    local isStorage = _G.GrindkeepStorage and _G.GrindkeepStorage.IsCurrentStorage() or false
    storageCheck:SetChecked(isStorage)
    local chars = DB.GetStorageChars and DB.GetStorageChars() or {}
    if #chars == 0 then
        storageInfo:SetText(L["STOCK_STORAGE_NONE"])
        return
    end
    local parts = {}
    for _, c in ipairs(chars) do
        local bank = c.bankAt and date(L["DATE_FORMAT_SHORT"], c.bankAt) or L["STORAGE_BANK_NEVER"]
        table.insert(parts, string.format(L["STOCK_STORAGE_ENTRY"], c.name, bank))
    end
    storageInfo:SetText(L["STOCK_STORAGE_PREFIX"] .. " " .. table.concat(parts, "  /  "))
end

Refresh = function()
    if not StockFrame:IsShown() then return end

    local inv = DB.GetInventory()
    if inv and inv.scannedAt then
        scannedAtText:SetText(string.format(L["STOCK_SCANNED_AT"], date(L["DATE_FORMAT_SHORT"], inv.scannedAt)))
    else
        scannedAtText:SetText(L["STOCK_NEVER_SCANNED"])
    end

    HighlightSources()
    RefreshStorageInfo()
    local rows = BuildRows()
    listBox:SetDataProvider(CreateDataProvider(rows), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)

    if #rows == 0 then
        emptyText:SetText(onlyMissing and L["STOCK_EMPTY_MISSING"] or L["STOCK_EMPTY"])
        emptyText:Show()
    else
        emptyText:Hide()
    end
end

StockFrame:SetScript("OnShow", Refresh)

-- Seit 1.1 ist der Bestand eine Seite im Hauptfenster.
local embedded = false

local function Toggle()
    if embedded and _G.GrindkeepUI and _G.GrindkeepUI.ToggleTab then
        _G.GrindkeepUI.ToggleTab("stock")
    elseif StockFrame:IsShown() then
        StockFrame:Hide()
    else
        StockFrame:Show()
    end
end

local function Embed(parent)
    if embedded then return StockFrame end
    embedded = true
    _G.GrindkeepStyle.EmbedFrame(StockFrame, parent)
    header:Hide()
    watermark:Hide()
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", StockFrame, "TOPLEFT", 0, 0)
    body:SetPoint("BOTTOMRIGHT", StockFrame, "BOTTOMRIGHT", 0, 0)
    -- "Erfasst am ..." stand in der eigenen Kopfzeile - jetzt neben die Knoepfe
    scannedAtText:SetParent(body)
    scannedAtText:ClearAllPoints()
    scannedAtText:SetPoint("LEFT", rescanBtn, "RIGHT", 12, 0)
    return StockFrame
end

_G.GrindkeepStockUI = {
    Frame = StockFrame,
    Toggle = Toggle,
    Show = function()
        if embedded and _G.GrindkeepUI and _G.GrindkeepUI.ShowTab then
            _G.GrindkeepUI.ShowTab("stock")
        else
            StockFrame:Show()
        end
    end,
    Refresh = Refresh,
    Embed = Embed,
}

if _G.GrindkeepStyle then
    _G.GrindkeepStyle.RegisterAndApply(StockFrame)
end

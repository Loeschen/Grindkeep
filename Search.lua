--[[
    Grindkeep - Search.lua

    Suche und Filter ueber alle gespeicherten Gildenbank-Vorgaenge:
    "Wer hat die Flaeschchen genommen?", "Was ist diese Woche an Gold
    rausgegangen?", "Alles von Spieler X samt Twinks".

    - Suchfeld: Teil eines Spieler-, Item- oder Fachnamens. Ein per
      Shift-Klick eingefuegter Itemlink sucht exakt nach diesem Item.
    - Art: alle, Einzahlungen, Entnahmen, nur Gold, nur Gegenstaende.
    - Zeitraum: gesamter Verlauf oder die letzten 7/30/90 Tage.
    - Unter der Liste steht die Summe der Treffer.

    Die eigentliche Suche steckt in Database.SearchTransactions, dieses
    Fenster ist nur die Oberflaeche dafuer.
]]

local DB = _G.GrindkeepDatabase
local L = _G.GrindkeepLocale

local C = {
    bg      = { 18 / 255, 18 / 255, 22 / 255, 0.95 },
    panelBg = { 24 / 255, 24 / 255, 29 / 255, 0.95 },
    border  = { 0x2a / 255, 0x2d / 255, 0x34 / 255, 1 },
    accent  = { 0xc9 / 255, 0xa2 / 255, 0x27 / 255, 1 },
    green   = { 0x2e / 255, 0xcc / 255, 0x71 / 255, 1 },
    red     = { 0xe7 / 255, 0x4c / 255, 0x3c / 255, 1 },
    neutral = { 0.8, 0.8, 0.85, 1 },
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
    if not itemID then return nil end
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

local function Coins(copper)
    if GetCoinTextureString then return GetCoinTextureString(copper or 0) end
    return tostring(math.floor((copper or 0) / 10000)) .. "g"
end

local EDGE = 13
local ROW_HEIGHT = 32

-- ============================================================
-- Fenster
-- ============================================================
local SearchFrame = CreateFrame("Frame", "GrindkeepSearchFrame", UIParent, "BackdropTemplate")
SearchFrame:SetSize(560, 460)
SearchFrame:SetPoint("CENTER", -60, 20)
SearchFrame:SetFrameStrata("HIGH")
SearchFrame:SetMovable(true)
SearchFrame:EnableMouse(true)
SearchFrame:RegisterForDrag("LeftButton")
SearchFrame:SetScript("OnDragStart", SearchFrame.StartMoving)
SearchFrame:SetScript("OnDragStop", SearchFrame.StopMovingOrSizing)
ApplyWindowBackdrop(SearchFrame)
SearchFrame:Hide()
tinsert(UISpecialFrames, "GrindkeepSearchFrame")

SearchFrame:SetResizable(true)
if SearchFrame.SetResizeBounds then
    SearchFrame:SetResizeBounds(460, 320, 1400, 1000)
else
    if SearchFrame.SetMinResize then SearchFrame:SetMinResize(460, 320) end
    if SearchFrame.SetMaxResize then SearchFrame:SetMaxResize(1400, 1000) end
end
SearchFrame:SetScript("OnMouseDown", function(self, button)
    if button == "LeftButton" and IsShiftKeyDown() then self:StartSizing("BOTTOMRIGHT") end
end)
SearchFrame:SetScript("OnMouseUp", function(self) self:StopMovingOrSizing() end)

local header = CreateFrame("Frame", nil, SearchFrame, "BackdropTemplate")
header:SetHeight(36)
header:SetPoint("TOPLEFT", EDGE, -EDGE)
header:SetPoint("TOPRIGHT", -EDGE, -EDGE)
Backdrop(header, C.panelBg, C.border)
header:EnableMouse(true)
header:RegisterForDrag("LeftButton")
header:SetScript("OnDragStart", function()
    if IsShiftKeyDown() then SearchFrame:StartSizing("BOTTOMRIGHT") else SearchFrame:StartMoving() end
end)
header:SetScript("OnDragStop", function() SearchFrame:StopMovingOrSizing() end)

local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("LEFT", 10, 0)
title:SetText(L["SEARCH_WINDOW_TITLE"])

local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
closeBtn:SetPoint("RIGHT", -4, 0)
closeBtn:SetScript("OnClick", function() SearchFrame:Hide() end)

local body = CreateFrame("Frame", nil, SearchFrame)
body:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -8)
body:SetPoint("BOTTOMRIGHT", SearchFrame, "BOTTOMRIGHT", -EDGE, EDGE)

-- ============================================================
-- Filter
-- ============================================================
local Refresh -- Vorwaertsdeklaration

local state = {
    text = "",
    mode = "all",      -- all | deposit | withdraw | gold | item
    periodDays = nil,  -- nil = gesamter Verlauf
    player = nil,      -- Charakter inkl. Twinks (aus dem Kontextmenue)
}

local searchBox = CreateFrame("EditBox", nil, body, "InputBoxTemplate")
searchBox:SetSize(260, 22)
searchBox:SetPoint("TOPLEFT", body, "TOPLEFT", 8, -2)
searchBox:SetAutoFocus(false)
searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
searchBox:SetScript("OnTextChanged", function(self)
    state.text = self:GetText() or ""
    Refresh()
end)

local searchHint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
searchHint:SetPoint("LEFT", searchBox, "RIGHT", 10, 0)
searchHint:SetPoint("RIGHT", body, "RIGHT", -8, 0)
searchHint:SetJustifyH("LEFT")
searchHint:SetText(L["SEARCH_HINT"])

-- Per Shift-Klick auf ein Item den Link ins Suchfeld einfuegen, solange
-- es den Fokus hat.
local function InsertLinkHook(link)
    if SearchFrame:IsShown() and searchBox:HasFocus() and type(link) == "string" then
        searchBox:SetText(link)
    end
end
-- Neuere Clients: ChatFrameUtil.InsertLink, aeltere: ChatEdit_InsertLink.
-- Beide einhaken, falls es beide als getrennte Funktionen gibt.
local hookedInsertLink = false
if ChatFrameUtil and ChatFrameUtil.InsertLink then
    hooksecurefunc(ChatFrameUtil, "InsertLink", InsertLinkHook)
    hookedInsertLink = true
end
if ChatEdit_InsertLink and not (hookedInsertLink and ChatEdit_InsertLink == ChatFrameUtil.InsertLink) then
    hooksecurefunc("ChatEdit_InsertLink", InsertLinkHook)
end

local function MakeToggleRow(anchor, entries, onSelect)
    local buttons = {}
    local prev
    for _, e in ipairs(entries) do
        local btn = CreateFrame("Button", nil, body)
        btn:SetHeight(20)
        btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.label:SetPoint("CENTER")
        btn.label:SetText(e.label)
        btn:SetWidth(math.max(40, (btn.label:GetStringWidth() or 40) + 16))
        if prev then
            btn:SetPoint("LEFT", prev, "RIGHT", 4, 0)
        else
            btn:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
        end
        btn:SetScript("OnClick", function() onSelect(e.key) end)
        buttons[e.key] = btn
        prev = btn
    end
    return buttons, prev
end

local function Highlight(buttons, activeKey)
    local Theme = _G.GrindkeepTheme
    local on = Theme and Theme.Color("accent") or C.accent
    local off = Theme and Theme.Color("textDim") or C.textDim
    for key, btn in pairs(buttons) do
        btn.label:SetTextColor(unpack(key == activeKey and on or off))
    end
end

local modeAnchor = CreateFrame("Frame", nil, body)
modeAnchor:SetSize(1, 1)
modeAnchor:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", -6, 0)

local modeButtons = MakeToggleRow(modeAnchor, {
    { key = "all",      label = L["SEARCH_MODE_ALL"] },
    { key = "deposit",  label = L["SEARCH_MODE_DEPOSIT"] },
    { key = "withdraw", label = L["SEARCH_MODE_WITHDRAW"] },
    { key = "gold",     label = L["SEARCH_MODE_GOLD"] },
    { key = "item",     label = L["SEARCH_MODE_ITEM"] },
}, function(key)
    state.mode = key
    Refresh()
end)

local periodAnchor = CreateFrame("Frame", nil, body)
periodAnchor:SetSize(1, 1)
periodAnchor:SetPoint("TOPLEFT", modeButtons.all, "BOTTOMLEFT", 0, 0)

local periodButtons = MakeToggleRow(periodAnchor, {
    { key = "all", label = L["UI_PERIOD_ALL"] },
    { key = "7",   label = L["UI_PERIOD_7"] },
    { key = "30",  label = L["UI_PERIOD_30"] },
    { key = "90",  label = L["UI_PERIOD_90"] },
}, function(key)
    state.periodDays = tonumber(key)
    Refresh()
end)

-- Hinweis auf einen aktiven Spielerfilter samt Knopf zum Entfernen
local playerLabel = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
playerLabel:SetPoint("LEFT", periodButtons["90"], "RIGHT", 16, 0)
local playerClear = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
playerClear:SetSize(22, 18)
playerClear:SetPoint("LEFT", playerLabel, "RIGHT", 4, 0)
playerClear:SetText("x")
playerClear:SetScript("OnClick", function()
    state.player = nil
    Refresh()
end)

-- ============================================================
-- Liste
-- ============================================================
local summary = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
summary:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", 8, 4)
summary:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -8, 4)
summary:SetJustifyH("LEFT")

local listBox = CreateFrame("Frame", nil, body, "WowScrollBoxList")
listBox:SetPoint("TOPLEFT", periodButtons.all, "BOTTOMLEFT", 0, -8)
listBox:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -26, 24)

local listBar = CreateFrame("EventFrame", nil, body, "MinimalScrollBar")
listBar:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 4, 0)
listBar:SetPoint("BOTTOMLEFT", listBox, "BOTTOMRIGHT", 4, 0)

local ACTION_LABELS = {
    deposit = "SEARCH_ACTION_DEPOSIT",
    withdraw = "SEARCH_ACTION_WITHDRAW",
    withdrawal = "SEARCH_ACTION_WITHDRAW",
    move = "SEARCH_ACTION_MOVE",
    repair = "SEARCH_ACTION_REPAIR",
}

local function InitRow(button, tx)
    if not button.initialized then
        button.initialized = true

        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(22, 22)
        button.icon:SetPoint("LEFT", 4, 0)

        button.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        button.text:SetPoint("LEFT", button.icon, "RIGHT", 8, 6)
        button.text:SetPoint("RIGHT", -8, 6)
        button.text:SetJustifyH("LEFT")

        button.sub = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        button.sub:SetPoint("LEFT", button.icon, "RIGHT", 8, -8)
        button.sub:SetPoint("RIGHT", -8, -8)
        button.sub:SetJustifyH("LEFT")

        button:SetScript("OnEnter", function(self)
            if self.itemLink then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                pcall(GameTooltip.SetHyperlink, GameTooltip, self.itemLink)
                GameTooltip:Show()
            end
        end)
        button:SetScript("OnLeave", function() GameTooltip:Hide() end)
        if _G.GrindkeepStyle then _G.GrindkeepStyle.ApplyToFrame(button) end
    end

    local action = tx.action == "withdrawal" and "withdraw" or tx.action
    local actionLabel = ACTION_LABELS[action] and L[ACTION_LABELS[action]] or tostring(action)
    local color = (action == "deposit" and C.green) or (action == "withdraw" and C.red) or C.neutral

    local what
    if tx.kind == "gold" then
        button.icon:SetTexture(133784)
        button.itemLink = nil
        what = Coins(tx.amount)
    else
        button.icon:SetTexture(GetItemIconCompat(tx.itemID) or 134400)
        button.itemLink = tx.itemLink
        what = string.format("%dx %s", tx.count or 0, tx.itemName or tx.itemLink or L["CORE_ITEM_INFO_PENDING"])
    end

    button.text:SetText(string.format("%s  %s  %s", tx.player or "?", actionLabel, what))
    button.text:SetTextColor(unpack(color))

    local where = tx.kind == "gold" and L["UI_GOLD_LOG_LABEL"]
        or (tx.tabName or string.format(L["UI_TAB_LABEL"], tostring(tx.tab or "?")))
    button.sub:SetText(string.format("%s  -  %s", tx.ts and date(L["DATE_FORMAT"], tx.ts) or "?", where))
end

local view = CreateScrollBoxListLinearView()
view:SetElementExtent(ROW_HEIGHT)
view:SetElementFactory(function(factory)
    factory("Frame", InitRow)
end)
ScrollUtil.InitScrollBoxListWithScrollBar(listBox, listBar, view)

-- ============================================================
-- Aktualisieren
-- ============================================================
local function BuildFilter()
    local filter = { limit = 500 }
    local text = state.text or ""
    local itemID = tonumber(text:match("|Hitem:(%d+)") or text:match("^item:(%d+)"))
    if itemID then
        filter.itemID = itemID
    elseif text ~= "" then
        filter.text = text
    end
    if state.mode == "deposit" or state.mode == "withdraw" then
        filter.action = state.mode
    elseif state.mode == "gold" or state.mode == "item" then
        filter.kind = state.mode
    end
    if state.periodDays then
        filter.sinceTs = DB.Now() - state.periodDays * 86400
    end
    filter.player = state.player
    return filter
end

Refresh = function()
    Highlight(modeButtons, state.mode)
    Highlight(periodButtons, state.periodDays and tostring(state.periodDays) or "all")
    if state.player then
        playerLabel:SetText(string.format(L["SEARCH_PLAYER_FILTER"], state.player))
        playerLabel:Show()
        playerClear:Show()
    else
        playerLabel:Hide()
        playerClear:Hide()
    end

    if not SearchFrame:IsShown() then return end

    local results = DB.SearchTransactions(BuildFilter())
    listBox:SetDataProvider(CreateDataProvider(results))

    -- Summe der Treffer: Gegenstaende rein/raus, Gold rein/raus
    local itemsIn, itemsOut, goldIn, goldOut = 0, 0, 0, 0
    for _, tx in ipairs(results) do
        local action = tx.action == "withdrawal" and "withdraw" or tx.action
        if tx.kind == "gold" then
            if action == "deposit" then goldIn = goldIn + (tx.amount or 0)
            elseif action == "withdraw" then goldOut = goldOut + (tx.amount or 0) end
        else
            if action == "deposit" then itemsIn = itemsIn + (tx.count or 0)
            elseif action == "withdraw" then itemsOut = itemsOut + (tx.count or 0) end
        end
    end

    if #results == 0 then
        summary:SetText(L["SEARCH_NO_RESULTS"])
    else
        local line = string.format(L["SEARCH_SUMMARY"], #results, itemsIn, itemsOut, Coins(goldIn), Coins(goldOut))
        if #results >= 500 then line = line .. "  " .. L["SEARCH_LIMIT_HINT"] end
        summary:SetText(line)
    end
end

SearchFrame:SetScript("OnShow", function() Refresh() end)

-- Seit 1.1 ist die Suche eine Seite ("Vorgaenge") im Hauptfenster.
local embedded = false

local function ShowFrame()
    if embedded and _G.GrindkeepUI and _G.GrindkeepUI.ShowTab then
        _G.GrindkeepUI.ShowTab("search")
    else
        SearchFrame:Show()
    end
end

local function Show(text)
    if text ~= nil then
        state.player = nil -- neue Suche: Spielerfilter aus dem Kontextmenue aufheben
        searchBox:SetText(text)
        state.text = text
    end
    ShowFrame()
    Refresh()
end

local function Embed(parent)
    if embedded then return SearchFrame end
    embedded = true
    _G.GrindkeepStyle.EmbedFrame(SearchFrame, parent)
    header:Hide()
    body:ClearAllPoints()
    body:SetPoint("TOPLEFT", SearchFrame, "TOPLEFT", 0, -4)
    body:SetPoint("BOTTOMRIGHT", SearchFrame, "BOTTOMRIGHT", 0, 0)
    -- Der Zeitraum wird oben im Hauptfenster fuer alle Seiten gewaehlt.
    for _, b in pairs(periodButtons) do b:Hide() end
    listBox:ClearAllPoints()
    listBox:SetPoint("TOPLEFT", modeButtons.all, "BOTTOMLEFT", 0, -8)
    listBox:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -26, 24)
    playerLabel:ClearAllPoints()
    playerLabel:SetPoint("LEFT", modeButtons.item, "RIGHT", 16, 0)
    return SearchFrame
end

if _G.GrindkeepTheme then _G.GrindkeepTheme.OnChange(function() Refresh() end) end

_G.GrindkeepSearchUI = {
    Frame = SearchFrame,
    Refresh = function() if SearchFrame:IsShown() then Refresh() end end,
    Toggle = function()
        if embedded and _G.GrindkeepUI and _G.GrindkeepUI.ToggleTab then
            _G.GrindkeepUI.ToggleTab("search")
        elseif SearchFrame:IsShown() then SearchFrame:Hide() else Show() end
    end,
    Show = Show,
    ShowForPlayer = function(name)
        state.player = name
        searchBox:SetText("")
        state.text = ""
        Show()
    end,
    Embed = Embed,
    -- Aktueller Filter (fuer den Export "so, wie du es gerade anschaust")
    GetFilter = function()
        local f = BuildFilter()
        f.limit = nil
        return f
    end,
    SetPeriod = function(days)
        state.periodDays = days
        Refresh()
    end,
}

Refresh()

if _G.GrindkeepStyle then
    _G.GrindkeepStyle.RegisterAndApply(SearchFrame)
end

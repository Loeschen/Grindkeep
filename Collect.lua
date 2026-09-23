--[[
    Grindkeep - Collect.lua

    Sammelliste (seit 1.3): was die Gilde gerade sammelt.

    - Eintrag mit Gegenstand (per Shift-Klick einfuegen oder Namen
      eintippen): Grindkeep zaehlt den Stand selbst - Gildenbank und
      Lager-Twinks zusammen (Database.GetCollectList).
    - Eintrag mit freiem Text ("Gold fuer Fach 2"): den Stand setzt man
      per Rechtsklick von Hand.
    - Rechtsklick auf einen Eintrag: Menge, Notiz, Stand, erledigt, entfernen.
    - "Als Text exportieren" oeffnet das Export-Fenster (Discord, Tabelle).

    Laeuft als Seite im Hauptfenster (siehe Style.EmbedFrame / UI.lua).
]]

local DB = _G.GrindkeepDatabase
local L = _G.GrindkeepLocale

local function T() return _G.GrindkeepTheme end
local function Col(name, fallback)
    local th = T()
    return th and th.Color(name) or fallback or { 1, 1, 1, 1 }
end

local GREEN = { 0x2e / 255, 0xcc / 255, 0x71 / 255, 1 }
local ROW_HEIGHT = 44

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

local function ItemInfoCompat(query)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if not f then return nil end
    local ok, name, link = pcall(f, query)
    if ok then return name, link end
    return nil
end

local function PopupEditBox(popup)
    if not popup then return nil end
    return popup.EditBox or popup.editBox or (popup.GetEditBox and popup:GetEditBox())
end

local function Print(msg) print("|cff2ecc71[Grindkeep]|r " .. msg) end

-- ============================================================
-- Rahmen
-- ============================================================
local CollectFrame = CreateFrame("Frame", "GrindkeepCollectFrame", UIParent, "BackdropTemplate")
CollectFrame:SetSize(700, 420)
CollectFrame:SetPoint("CENTER")
CollectFrame:Hide()

local body = CreateFrame("Frame", nil, CollectFrame)
body:SetAllPoints(CollectFrame)

local Refresh -- Vorwaertsdeklaration

-- ============================================================
-- Neuer Eintrag
-- ============================================================
local addLabel = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
addLabel:SetPoint("TOPLEFT", body, "TOPLEFT", 2, -6)
addLabel:SetText(L["COLLECT_ADD_LABEL"])

local function MakeBox(width, placeholder)
    local box = CreateFrame("EditBox", nil, body, "InputBoxTemplate")
    box:SetSize(width, 20)
    box:SetAutoFocus(false)
    box:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    box.placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    box.placeholder:SetPoint("LEFT", 2, 0)
    box.placeholder:SetText(placeholder)
    local function Update(self)
        self.placeholder:SetShown((self:GetText() or "") == "" and not self:HasFocus())
    end
    box:SetScript("OnEditFocusGained", Update)
    box:SetScript("OnEditFocusLost", Update)
    box:SetScript("OnTextChanged", Update)
    if T() then T().SkinInput(box) end
    return box
end

local itemBox = MakeBox(230, L["COLLECT_ITEM_PLACEHOLDER"])
itemBox:SetPoint("TOPLEFT", addLabel, "BOTTOMLEFT", 6, -6)

local amountBox = MakeBox(60, L["COLLECT_AMOUNT_PLACEHOLDER"])
amountBox:SetPoint("LEFT", itemBox, "RIGHT", 12, 0)
amountBox:SetNumeric(true)
amountBox:SetMaxLetters(7)

local noteBox = MakeBox(200, L["COLLECT_NOTE_PLACEHOLDER"])
noteBox:SetPoint("LEFT", amountBox, "RIGHT", 12, 0)
noteBox:SetMaxLetters(DB.COLLECT_NOTE_MAX or 100)

local addBtn = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
addBtn:SetSize(100, 22)
addBtn:SetPoint("LEFT", noteBox, "RIGHT", 10, 0)
addBtn:SetText(L["COLLECT_ADD_BUTTON"])
if T() then T().SkinButton(addBtn) end

-- Shift-Klick auf einen Gegenstand fuegt ihn ins Feld ein, solange es den
-- Fokus hat (gleiches Verfahren wie im Vorgaenge-Reiter).
local function InsertLinkHook(link)
    if itemBox:IsVisible() and itemBox:HasFocus() and type(link) == "string" then
        itemBox:SetText(link)
    end
end
-- Beide Namen einhaken - ausser sie zeigen auf dieselbe Funktion (dann
-- wuerde der Link doppelt eingefuegt). Vergleich VOR dem Einhaken.
local utilInsert = ChatFrameUtil and ChatFrameUtil.InsertLink
local sameFunction = utilInsert ~= nil and utilInsert == ChatEdit_InsertLink
if utilInsert and hooksecurefunc then
    hooksecurefunc(ChatFrameUtil, "InsertLink", InsertLinkHook)
end
if ChatEdit_InsertLink and hooksecurefunc and not sameFunction then
    hooksecurefunc("ChatEdit_InsertLink", InsertLinkHook)
end

-- Text aus dem Feld deuten: Itemlink, Item-ID, bekannter Itemname oder
-- freier Text. Rueckgabe: itemID|nil, name, link|nil
local function ParseItemInput(text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return nil end
    local id = tonumber(text:match("|Hitem:(%d+)"))
    if id then
        local link = text:match("(|c[^|]*|Hitem:.-|h.-|h|r)") or text:match("(|Hitem:.-|h.-|h)")
        local name = text:match("|h%[(.-)%]|h")
        return id, name, link
    end
    id = tonumber(text:match("^(%d+)$"))
    if id then
        local name, link = ItemInfoCompat(id)
        return id, name, link
    end
    local name, link = ItemInfoCompat(text)
    if name and link then
        return tonumber(link:match("|Hitem:(%d+)")), name, link
    end
    return nil, text, nil
end

local function AddEntry()
    local itemID, name, link = ParseItemInput(itemBox:GetText())
    local amount = tonumber(amountBox:GetText())
    if not itemID and not name then
        Print(L["COLLECT_NEED_ITEM"])
        return
    end
    if not amount or amount < 1 then
        Print(L["COLLECT_NEED_AMOUNT"])
        amountBox:SetFocus()
        return
    end
    local id = DB.AddCollectEntry({
        itemID = itemID, itemName = name, itemLink = link,
        target = amount, note = noteBox:GetText(),
    })
    if not id then
        Print(L["COLLECT_ADD_FAILED"])
        return
    end
    itemBox:SetText(""); amountBox:SetText(""); noteBox:SetText("")
    itemBox:ClearFocus(); amountBox:ClearFocus(); noteBox:ClearFocus()
    Refresh()
end
addBtn:SetScript("OnClick", AddEntry)
itemBox:SetScript("OnEnterPressed", function() amountBox:SetFocus() end)
amountBox:SetScript("OnEnterPressed", function() noteBox:SetFocus() end)
noteBox:SetScript("OnEnterPressed", AddEntry)

local addHint = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
addHint:SetPoint("TOPLEFT", itemBox, "BOTTOMLEFT", -4, -6)
addHint:SetPoint("RIGHT", body, "RIGHT", -4, 0)
addHint:SetJustifyH("LEFT")
addHint:SetText(L["COLLECT_ADD_HINT"])

-- ============================================================
-- Filter und Export
-- ============================================================
local showDone = false
local filterButtons = {}
local filterLabel = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
filterLabel:SetPoint("TOPLEFT", addHint, "BOTTOMLEFT", 0, -12)
filterLabel:SetText(L["COLLECT_SHOW_LABEL"])

local prev = filterLabel
for _, e in ipairs({ { key = false, label = L["COLLECT_SHOW_OPEN"] }, { key = true, label = L["COLLECT_SHOW_ALL"] } }) do
    local b = CreateFrame("Button", nil, body)
    b:SetHeight(18)
    b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    b.label:SetPoint("CENTER")
    b.label:SetText(e.label)
    b:SetWidth(math.max(40, (tonumber(b.label:GetStringWidth()) or 40) + 16))
    b:SetPoint("LEFT", prev, "RIGHT", prev == filterLabel and 8 or 2, 0)
    b:SetScript("OnClick", function() showDone = e.key; Refresh() end)
    b.key = e.key
    table.insert(filterButtons, b)
    prev = b
end

local summaryText = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
summaryText:SetPoint("LEFT", prev, "RIGHT", 16, 0)

local exportBtn = CreateFrame("Button", nil, body, "UIPanelButtonTemplate")
exportBtn:SetSize(150, 20)
exportBtn:SetPoint("RIGHT", body, "RIGHT", -2, 0)
exportBtn:SetPoint("TOP", filterLabel, "TOP", 0, 3)
exportBtn:SetText(L["COLLECT_EXPORT_BUTTON"])
exportBtn:SetScript("OnClick", function()
    if _G.GrindkeepExportUI then _G.GrindkeepExportUI.Show("collect") end
end)
if T() then T().SkinButton(exportBtn) end

-- ============================================================
-- Liste
-- ============================================================
local listBox = CreateFrame("Frame", nil, body, "WowScrollBoxList")
listBox:SetPoint("TOPLEFT", filterLabel, "BOTTOMLEFT", -2, -10)
listBox:SetPoint("BOTTOMRIGHT", body, "BOTTOMRIGHT", -22, 2)

local listBar = CreateFrame("EventFrame", nil, body, "MinimalScrollBar")
listBar:SetPoint("TOPLEFT", listBox, "TOPRIGHT", 4, 0)
listBar:SetPoint("BOTTOMLEFT", listBox, "BOTTOMRIGHT", 4, 0)

local emptyText = body:CreateFontString(nil, "OVERLAY", "GameFontDisable")
emptyText:SetPoint("TOP", listBox, "TOP", 0, -30)
emptyText:SetWidth(420)
emptyText:SetJustifyH("CENTER")
emptyText:Hide()

-- ---------- Bearbeiten per Rechtsklick ----------
local EDIT_FIELDS = {
    target = { title = "COLLECT_EDIT_TARGET", numeric = true },
    note = { title = "COLLECT_EDIT_NOTE", numeric = false },
    manualHave = { title = "COLLECT_EDIT_HAVE", numeric = true },
}

local function AcceptEdit(popup)
    local data = popup and popup.data
    local eb = PopupEditBox(popup)
    if not data or not eb then return end
    local value = eb:GetText() or ""
    local spec = EDIT_FIELDS[data.field]
    if spec and spec.numeric then value = tonumber(value) end
    if value == nil or not DB.UpdateCollectEntry(data.id, { [data.field] = value }) then
        Print(L["COLLECT_EDIT_INVALID"])
        return
    end
    Refresh()
end

StaticPopupDialogs["GRINDKEEP_COLLECT_EDIT"] = {
    text = "%s",
    button1 = OKAY,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 100,
    OnShow = function(self, data)
        local eb = PopupEditBox(self)
        data = data or self.data
        if eb and data then
            eb.gkPopup = self
            eb:SetText(tostring(data.current or ""))
            eb:HighlightText()
            eb:SetFocus()
        end
    end,
    OnAccept = function(self) AcceptEdit(self) end,
    EditBoxOnEnterPressed = function(self)
        local popup = self.gkPopup or self:GetParent()
        AcceptEdit(popup)
        popup:Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        local popup = self.gkPopup or self:GetParent()
        popup:Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

StaticPopupDialogs["GRINDKEEP_COLLECT_REMOVE"] = {
    text = "%s",
    button1 = YES or OKAY,
    button2 = NO or CANCEL,
    OnAccept = function(self)
        local id = self.data
        if id and DB.RemoveCollectEntry(id) then Refresh() end
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

local function EditField(entry, field)
    local spec = EDIT_FIELDS[field]
    local current = entry[field == "manualHave" and "have" or field]
    StaticPopup_Show("GRINDKEEP_COLLECT_EDIT",
        string.format(L[spec.title], entry.itemName or "?"), nil,
        { id = entry.id, field = field, current = current })
end

local function ToggleDone(entry)
    DB.UpdateCollectEntry(entry.id, { done = not entry.done })
    Refresh()
end

local function RemoveEntry(entry)
    StaticPopup_Show("GRINDKEEP_COLLECT_REMOVE",
        string.format(L["COLLECT_REMOVE_CONFIRM"], entry.itemName or "?"), nil, entry.id)
end

local function ShowEntryMenu(owner, entry)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        EditField(entry, "target") -- ohne Menue-System: wenigstens die Menge
        return
    end
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(entry.itemName or "?")
        root:CreateButton(L["COLLECT_MENU_TARGET"], function() EditField(entry, "target") end)
        if entry.manual then
            root:CreateButton(L["COLLECT_MENU_HAVE"], function() EditField(entry, "manualHave") end)
        end
        root:CreateButton(L["COLLECT_MENU_NOTE"], function() EditField(entry, "note") end)
        root:CreateButton(entry.done and L["COLLECT_MENU_REOPEN"] or L["COLLECT_MENU_DONE"], function() ToggleDone(entry) end)
        root:CreateDivider()
        root:CreateButton(L["COLLECT_MENU_REMOVE"], function() RemoveEntry(entry) end)
    end)
end

-- ---------- Zeilen ----------
local function InitRow(button, entry)
    if not button.initialized then
        button.initialized = true
        button.hl = button:CreateTexture(nil, "BACKGROUND")
        button.hl:SetAllPoints()
        button.hl:Hide()

        button.icon = button:CreateTexture(nil, "ARTWORK")
        button.icon:SetSize(28, 28)
        button.icon:SetPoint("LEFT", 6, 0)

        button.count = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.count:SetPoint("TOPRIGHT", -8, -6)

        button.name = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        button.name:SetPoint("TOPLEFT", button.icon, "TOPRIGHT", 10, 1)
        button.name:SetPoint("RIGHT", button.count, "LEFT", -8, 0)
        button.name:SetJustifyH("LEFT")
        button.name:SetWordWrap(false)

        button.bar = CreateFrame("StatusBar", nil, button)
        button.bar:SetHeight(4)
        button.bar:SetPoint("LEFT", button.icon, "RIGHT", 10, -2)
        button.bar:SetPoint("RIGHT", button, "RIGHT", -8, 0)
        button.bar:SetStatusBarTexture("Interface\\Buttons\\WHITE8x8")
        button.bar:SetMinMaxValues(0, 1)
        button.barBg = button.bar:CreateTexture(nil, "BACKGROUND")
        button.barBg:SetAllPoints()

        button.sub = button:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
        button.sub:SetPoint("BOTTOMLEFT", button.icon, "BOTTOMRIGHT", 10, -2)
        button.sub:SetPoint("RIGHT", button, "RIGHT", -8, 0)
        button.sub:SetJustifyH("LEFT")
        button.sub:SetWordWrap(false)

        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        button:SetScript("OnEnter", function(self)
            self.hl:Show()
            local e = self.entry
            if not e then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            if e.itemLink then
                pcall(GameTooltip.SetHyperlink, GameTooltip, e.itemLink)
            else
                GameTooltip:SetText(e.itemName or "?", 1, 1, 1)
            end
            GameTooltip:AddLine(" ")
            if e.manual then
                GameTooltip:AddLine(L["COLLECT_TIP_MANUAL"], 0.8, 0.8, 0.8, true)
            elseif #e.sources > 0 or e.haveBank > 0 then
                GameTooltip:AddLine(L["STOCK_WHERE"], 1, 0.82, 0)
                if e.haveBank > 0 then GameTooltip:AddDoubleLine(L["STOCK_SOURCE_BANK"], tostring(e.haveBank), 1, 1, 1, 1, 1, 1) end
                for _, s in ipairs(e.sources) do GameTooltip:AddDoubleLine(s.name, tostring(s.count), 1, 1, 1, 1, 1, 1) end
            else
                GameTooltip:AddLine(L["COLLECT_TIP_NONE"], 0.8, 0.8, 0.8, true)
            end
            if e.createdBy then
                GameTooltip:AddLine(string.format(L["COLLECT_TIP_BY"], e.createdBy,
                    e.createdAt and date(L["DATE_FORMAT_SHORT"], e.createdAt) or "?"), 0.6, 0.6, 0.6)
            end
            GameTooltip:AddLine(L["COLLECT_TIP_RIGHTCLICK"], 0.6, 0.6, 0.6)
            GameTooltip:Show()
        end)
        button:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
        button:SetScript("OnClick", function(self, mouse)
            if mouse == "RightButton" and self.entry then ShowEntryMenu(self, self.entry) end
        end)
        if _G.GrindkeepStyle then _G.GrindkeepStyle.ApplyToFrame(button) end
    end

    button.entry = entry
    button.hl:SetColorTexture(unpack(Col("rowHover", { 1, 1, 1, 0.05 })))
    button.barBg:SetColorTexture(unpack(Col("line", { 0.2, 0.2, 0.25, 1 })))
    button.icon:SetTexture(GetItemIconCompat(entry.itemID) or (entry.manual and "Interface\\Icons\\INV_Misc_Note_01") or 134400)
    button.name:SetText(entry.itemLink or entry.itemName or "?")
    button.count:SetText(string.format("%d / %d", entry.have, entry.target))
    local barColor = entry.reached and GREEN or Col("accent", GREEN)
    button.bar:SetStatusBarColor(unpack(barColor))
    button.bar:SetValue(entry.progress or 0)
    button.count:SetTextColor(unpack(entry.reached and GREEN or Col("text", { 1, 1, 1, 1 })))

    local parts = {}
    if entry.done then
        table.insert(parts, L["COLLECT_DONE"])
    elseif entry.reached then
        table.insert(parts, L["COLLECT_REACHED"])
    else
        table.insert(parts, string.format(L["COLLECT_MISSING"], entry.missing))
    end
    if entry.manual then table.insert(parts, L["COLLECT_MANUAL"]) end
    if entry.note then table.insert(parts, entry.note) end
    button.sub:SetText(table.concat(parts, "  -  "))
    button:SetAlpha(entry.done and 0.5 or 1)
end

local view = CreateScrollBoxListLinearView()
view:SetElementExtent(ROW_HEIGHT)
view:SetElementFactory(function(factory)
    factory("Button", InitRow)
end)
ScrollUtil.InitScrollBoxListWithScrollBar(listBox, listBar, view)

-- ============================================================
-- Aktualisieren
-- ============================================================
local function HighlightFilter()
    for _, b in ipairs(filterButtons) do
        b.label:SetTextColor(unpack(b.key == showDone and Col("accent") or Col("textMid", { 0.8, 0.8, 0.8, 1 })))
    end
end

Refresh = function()
    HighlightFilter()
    if not CollectFrame:IsShown() then return end
    local list = DB.GetCollectList(showDone)
    listBox:SetDataProvider(CreateDataProvider(list), ScrollBoxConstants and ScrollBoxConstants.RetainScrollPosition)

    local all = DB.GetCollectList(true)
    local open, reached = 0, 0
    for _, e in ipairs(all) do
        if not e.done then
            open = open + 1
            if e.reached then reached = reached + 1 end
        end
    end
    summaryText:SetText(string.format(L["COLLECT_SUMMARY"], open, reached))

    if #list == 0 then
        emptyText:SetText(#all == 0 and L["COLLECT_EMPTY"] or L["COLLECT_EMPTY_OPEN"])
        emptyText:Show()
    else
        emptyText:Hide()
    end
end

CollectFrame:SetScript("OnShow", function() Refresh() end)
if T() then T().OnChange(function() Refresh() end) end

-- ============================================================
-- Einbetten ins Hauptfenster
-- ============================================================
local embedded = false
local function Embed(parent)
    if embedded then return CollectFrame end
    embedded = true
    _G.GrindkeepStyle.EmbedFrame(CollectFrame, parent)
    return CollectFrame
end

_G.GrindkeepCollectUI = {
    Frame = CollectFrame,
    Embed = Embed,
    Refresh = function() if CollectFrame:IsShown() then Refresh() end end,
    Show = function()
        if embedded and _G.GrindkeepUI and _G.GrindkeepUI.ShowTab then
            _G.GrindkeepUI.ShowTab("collect")
        else
            CollectFrame:Show()
        end
    end,
    -- Nur fuer Tests
    _ParseItemInput = ParseItemInput,
    _AddFromFields = function(item, amount, note)
        itemBox:SetText(item or ""); amountBox:SetText(amount or ""); noteBox:SetText(note or "")
        AddEntry()
    end,
}

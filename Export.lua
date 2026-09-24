--[[
    Grindkeep - Export.lua

    Allgemeiner Export (seit 1.3): Daten als Text zum Kopieren.

      Inhalt:  Sammelliste | Bestand | Vorgaenge | Bilanzen
      Format:  Discord  - fertig formatiert (Fettschrift, Listen). Discord
                          erlaubt 2000 Zeichen je Nachricht, laengere
                          Texte werden in Teile zerlegt ("Teil 1/3").
               Tabelle  - mit Semikolon getrennt, direkt in Excel oder
                          Google Tabellen einfuegbar.
               Text     - schlichte Zeilen, z.B. fuer ein Forum.

    WoW laesst Addons weder in die Zwischenablage schreiben noch Dateien
    anlegen. Deshalb landet der Text markiert in einem Textfeld; kopieren
    muss man selbst mit Strg+C.

    Nicht verwechseln mit "/gkeep export" (Comm.lua): das ist der
    Datenaustausch zwischen Grindkeep-Nutzern, nicht zum Lesen gedacht.

    Die Textbausteine (Export.Build) sind reine Funktionen ohne Fenster -
    so lassen sie sich ausserhalb des Spiels testen.
]]

local DB = _G.GrindkeepDatabase
local L = _G.GrindkeepLocale

local Export = {}
_G.GrindkeepExport = Export

local DISCORD_LIMIT = 1900 -- etwas Luft unter Discords 2000 Zeichen

-- ------------------------------------------------------------
-- Hilfen
-- ------------------------------------------------------------
-- WoW-Steuerzeichen entfernen: Farben, Links, Texturen. Uebrig bleibt der
-- lesbare Text; "|" selbst darf im Ergebnis nie vorkommen (im Textfeld
-- waere es ein Steuerzeichen).
local function Plain(text)
    if type(text) ~= "string" then return "" end
    text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]*:", ""):gsub("|r", "")
    text = text:gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""):gsub("|A.-|a", "")
    text = text:gsub("|", "/")
    return text
end

local function ItemName(e)
    local n = e.itemName or (e.itemLink and e.itemLink:match("|h%[(.-)%]|h"))
    if not n and e.itemID then n = string.format(L["ITEM_FALLBACK"], tostring(e.itemID)) end
    return Plain(n or "?")
end

-- Zeichen, die Discord als Formatierung liest, entschaerfen
local function DiscordEscape(text)
    local t = Plain(text):gsub("([%*_~`>\\])", "\\%1")
    -- "@everyone"/"@here" sollen beim Einfuegen niemanden anpingen
    t = t:gsub("@", "@\226\128\139")
    return t
end

local function Money(copper)
    copper = math.floor(math.abs(copper or 0))
    local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
    local parts = {}
    if g > 0 then table.insert(parts, g .. "g") end
    if s > 0 then table.insert(parts, s .. "s") end
    if c > 0 or #parts == 0 then table.insert(parts, c .. "c") end
    return table.concat(parts, " ")
end

local function SignedMoney(copper)
    if (copper or 0) < 0 then return "-" .. Money(copper) end
    if (copper or 0) > 0 then return "+" .. Money(copper) end
    return Money(0)
end

-- Gold als Dezimalzahl fuer Tabellen (deutsches Komma, sonst Punkt)
local function GoldNumber(copper)
    local s = string.format("%.4f", (copper or 0) / 10000)
    s = s:gsub("0+$", ""):gsub("%.$", "")
    if GetLocale and GetLocale() == "deDE" then s = s:gsub("%.", ",") end
    return s
end

local function CsvField(v)
    v = Plain(tostring(v == nil and "" or v))
    if v:find('[;"\n]') then v = '"' .. v:gsub('"', '""') .. '"' end
    return v
end

local function CsvLine(fields)
    local out = {}
    for i, f in ipairs(fields) do out[i] = CsvField(f) end
    return table.concat(out, ";")
end

local function GuildName()
    local name = GetGuildInfo and GetGuildInfo("player")
    return type(name) == "string" and name or ""
end

local function Today()
    return date(L["DATE_FORMAT_SHORT"])
end

local function PeriodDays()
    return _G.GrindkeepUI and _G.GrindkeepUI.GetPeriodDays and _G.GrindkeepUI.GetPeriodDays() or nil
end

local function PeriodText(days)
    if days then return string.format(L["EXPORT_PERIOD_DAYS"], days) end
    return L["EXPORT_PERIOD_ALL"]
end

-- ------------------------------------------------------------
-- Inhalte: jede Funktion liefert title, header (Tabelle), rows.
-- rows: { discord = "...", text = "...", csv = { ... } }
-- ------------------------------------------------------------
local Sources = {}

Sources.collect = function()
    local rows = {}
    for _, e in ipairs(DB.GetCollectList(false)) do
        local name = ItemName(e)
        local status = e.reached and L["EXPORT_REACHED"] or string.format(L["EXPORT_MISSING"], e.missing)
        local note = e.note and (" (" .. Plain(e.note) .. ")") or ""
        table.insert(rows, {
            discord = string.format("- **%s**: %d / %d - %s%s", DiscordEscape(name), e.have, e.target,
                e.reached and status or ("**" .. status .. "**"), e.note and (" _(" .. DiscordEscape(e.note) .. ")_") or ""),
            text = string.format("- %s: %d / %d - %s%s", name, e.have, e.target, status, note),
            csv = { name, e.have, e.target, e.missing, e.note or "" },
        })
    end
    return {
        title = L["EXPORT_TITLE_COLLECT"],
        header = { L["EXPORT_COL_ITEM"], L["EXPORT_COL_HAVE"], L["EXPORT_COL_TARGET"], L["EXPORT_COL_MISSING"], L["EXPORT_COL_NOTE"] },
        rows = rows,
        empty = L["EXPORT_EMPTY_COLLECT"],
    }
end

Sources.stock = function()
    local rows = {}
    local missing = DB.GetStockList(true)
    if #missing > 0 then
        table.insert(rows, { discord = "**" .. L["EXPORT_STOCK_MISSING"] .. "**", text = L["EXPORT_STOCK_MISSING"], csv = nil })
        for _, e in ipairs(missing) do
            local name = ItemName(e)
            table.insert(rows, {
                discord = string.format("- **%s**: %d / %d - %s", DiscordEscape(name), e.have, e.required,
                    string.format(L["EXPORT_MISSING"], e.missing)),
                text = string.format("- %s: %d / %d - %s", name, e.have, e.required, string.format(L["EXPORT_MISSING"], e.missing)),
                csv = nil,
            })
        end
        table.insert(rows, { discord = "", text = "", csv = nil })
        table.insert(rows, { discord = "**" .. L["EXPORT_STOCK_HAVE"] .. "**", text = L["EXPORT_STOCK_HAVE"], csv = nil })
    end
    local mins = DB.GetMinimums()
    local listed = {}
    for _, e in ipairs(DB.GetCombinedInventory("all")) do listed[e.itemID] = true end
    -- Fehlende Gegenstaende, von denen gar nichts da ist, fuer die Tabelle
    for _, e in ipairs(missing) do
        if not listed[e.itemID] then
            table.insert(rows, { discord = nil, text = nil, csv = { ItemName(e), 0, 0, 0, e.required } })
        end
    end
    for _, e in ipairs(DB.GetCombinedInventory("all")) do
        local name = ItemName(e)
        table.insert(rows, {
            discord = string.format("- %dx %s", e.count, DiscordEscape(name)),
            text = string.format("- %dx %s", e.count, name),
            csv = { name, e.count, e.bankCount, e.storageCount, mins[e.itemID] and mins[e.itemID].count or "" },
        })
    end
    return {
        title = L["EXPORT_TITLE_STOCK"],
        header = { L["EXPORT_COL_ITEM"], L["EXPORT_COL_TOTAL"], L["EXPORT_COL_BANK"], L["EXPORT_COL_STORAGE"], L["EXPORT_COL_MINIMUM"] },
        rows = rows,
        empty = L["EXPORT_EMPTY_STOCK"],
    }
end

local ACTION_KEYS = { deposit = "SEARCH_ACTION_DEPOSIT", withdraw = "SEARCH_ACTION_WITHDRAW",
    withdrawal = "SEARCH_ACTION_WITHDRAW", move = "SEARCH_ACTION_MOVE", repair = "SEARCH_ACTION_REPAIR" }

Sources.tx = function()
    local filter
    if _G.GrindkeepSearchUI and _G.GrindkeepSearchUI.GetFilter then
        filter = _G.GrindkeepSearchUI.GetFilter()
    end
    filter = filter or {}
    local days = PeriodDays()
    if filter.sinceTs == nil and days then filter.sinceTs = DB.Now() - days * 86400 end
    filter.limit = 500
    local rows = {}
    for _, tx in ipairs(DB.SearchTransactions(filter)) do
        local action = tx.action == "withdrawal" and "withdraw" or tx.action
        local verb = ACTION_KEYS[action] and L[ACTION_KEYS[action]] or tostring(action)
        local what, where
        if tx.kind == "gold" then
            what = Money(tx.amount)
            where = L["UI_GOLD_LOG_LABEL"]
        else
            what = string.format("%dx %s", tx.count or 0, ItemName(tx))
            where = Plain(tx.tabName or string.format(L["UI_TAB_LABEL"], tostring(tx.tab or "?")))
        end
        local when = tx.ts and date(L["DATE_FORMAT"], tx.ts) or "?"
        local player = Plain(tx.player or "?")
        table.insert(rows, {
            discord = string.format("- %s - **%s** %s %s _(%s)_", when, DiscordEscape(player), verb, DiscordEscape(what), DiscordEscape(where)),
            text = string.format("- %s - %s %s %s (%s)", when, player, verb, what, where),
            csv = { when, player, verb, tx.kind == "gold" and GoldNumber(tx.amount) or "",
                tx.kind == "item" and (tx.count or 0) or "", tx.kind == "item" and ItemName(tx) or "", where },
        })
    end
    return {
        title = L["EXPORT_TITLE_TX"] .. " - " .. PeriodText(days),
        header = { L["EXPORT_COL_WHEN"], L["EXPORT_COL_PLAYER"], L["EXPORT_COL_ACTION"], L["EXPORT_COL_GOLD"],
            L["EXPORT_COL_COUNT"], L["EXPORT_COL_ITEM"], L["EXPORT_COL_WHERE"] },
        rows = rows,
        empty = L["EXPORT_EMPTY_TX"],
    }
end

Sources.balances = function()
    local days = PeriodDays()
    local since = days and (DB.Now() - days * 86400) or nil
    local rows = {}
    for i, e in ipairs(DB.GetPlayerList("net", since)) do
        local s = e.summary or {}
        local name = Plain(e.name)
        local detail = string.format(L["EXPORT_BALANCE_DETAIL"], Money(s.goldDeposited), Money(s.goldWithdrawn),
            s.itemDeposits or 0, s.itemWithdrawals or 0)
        table.insert(rows, {
            discord = string.format("%d. **%s**: %s - %s", i, DiscordEscape(name), SignedMoney(e.net), detail),
            text = string.format("%d. %s: %s - %s", i, name, SignedMoney(e.net), detail),
            csv = { name, GoldNumber(e.net), GoldNumber(s.goldDeposited), GoldNumber(s.goldWithdrawn),
                s.itemDeposits or 0, s.itemWithdrawals or 0 },
        })
    end
    return {
        title = L["EXPORT_TITLE_BALANCES"] .. " - " .. PeriodText(days),
        header = { L["EXPORT_COL_PLAYER"], L["EXPORT_COL_NET"], L["EXPORT_COL_GOLD_IN"], L["EXPORT_COL_GOLD_OUT"],
            L["EXPORT_COL_ITEMS_IN"], L["EXPORT_COL_ITEMS_OUT"] },
        rows = rows,
        empty = L["EXPORT_EMPTY_BALANCES"],
    }
end

Export.Kinds = { "collect", "stock", "tx", "balances" }
Export.Formats = { "discord", "csv", "text" }

-- Zeilen in Discord-Teile packen; jeder Teil bekommt die Ueberschrift
local function PackDiscord(heading, lines)
    local chunks, current = {}, {}
    local size = 0
    local reserve = #heading + 20 -- Platz fuer " (Teil 10/10)"
    for _, line in ipairs(lines) do
        if #line > DISCORD_LIMIT - reserve then line = DB.Utf8Cut(line, DISCORD_LIMIT - reserve - 3) .. "..." end
        if size + #line + 1 > DISCORD_LIMIT - reserve and #current > 0 then
            table.insert(chunks, current)
            current, size = {}, 0
        end
        table.insert(current, line)
        size = size + #line + 1
    end
    if #current > 0 or #chunks == 0 then table.insert(chunks, current) end
    local out = {}
    for i, c in ipairs(chunks) do
        local head = heading
        if #chunks > 1 then head = head .. string.format(" " .. L["EXPORT_PART"], i, #chunks) end
        table.insert(out, head .. "\n" .. table.concat(c, "\n"))
    end
    return out
end

-- Liefert eine Liste von Texten (bei Discord ggf. mehrere Teile)
function Export.Build(kind, format)
    local src = Sources[kind]
    if not src then return { "" } end
    local data = src()
    local guild = GuildName()
    local titleLine = data.title .. (guild ~= "" and (" - " .. guild) or "")

    if format == "csv" then
        local lines = { CsvLine(data.header) }
        for _, r in ipairs(data.rows) do
            if r.csv then table.insert(lines, CsvLine(r.csv)) end
        end
        return { table.concat(lines, "\n") }
    end

    if #data.rows == 0 then
        if format == "discord" then return { "**" .. DiscordEscape(titleLine) .. "**\n" .. data.empty } end
        return { titleLine .. "\n" .. data.empty }
    end

    if format == "discord" then
        local lines = {}
        for _, r in ipairs(data.rows) do if r.discord then table.insert(lines, r.discord) end end
        local heading = "**" .. DiscordEscape(titleLine) .. "** (" .. string.format(L["EXPORT_AS_OF"], Today()) .. ")"
        return PackDiscord(heading, lines)
    end

    local lines = { titleLine .. " (" .. string.format(L["EXPORT_AS_OF"], Today()) .. ")", "" }
    for _, r in ipairs(data.rows) do if r.text then table.insert(lines, r.text) end end
    return { table.concat(lines, "\n") }
end

-- Nur fuer Tests
Export._Plain = Plain
Export._DiscordEscape = DiscordEscape
Export._CsvLine = CsvLine
Export._Money = Money
Export._PackDiscord = PackDiscord

-- ============================================================
-- Fenster
-- ============================================================
local Theme = _G.GrindkeepTheme
local state = { kind = "collect", format = "discord", part = 1, chunks = { "" } }

local Frame = CreateFrame("Frame", "GrindkeepExportFrame", UIParent, "BackdropTemplate")
Frame:SetSize(640, 470)
Frame:SetPoint("CENTER", 40, 0)
Frame:SetFrameStrata("DIALOG")
Frame:SetToplevel(true)
Frame:SetMovable(true)
Frame:EnableMouse(true)
Frame:RegisterForDrag("LeftButton")
Frame:SetScript("OnDragStart", Frame.StartMoving)
Frame:SetScript("OnDragStop", Frame.StopMovingOrSizing)
Frame:SetClampedToScreen(true)
Frame:Hide()
tinsert(UISpecialFrames, "GrindkeepExportFrame")
if Theme then Theme.Skin(Frame, "window") end

local title = Frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 22, -20)
title:SetText(L["EXPORT_WINDOW_TITLE"])
if Theme then Theme.TextColor(title, "title") end

local closeBtn = CreateFrame("Button", nil, Frame, "UIPanelCloseButton")
closeBtn:SetPoint("TOPRIGHT", -12, -12)
closeBtn:SetScript("OnClick", function() Frame:Hide() end)
if Theme then Theme.SkinClose(closeBtn) end

local Rebuild -- Vorwaertsdeklaration

local function ToggleRow(anchor, labelText, entries, getter, setter, yOffset)
    local label = Frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, yOffset)
    label:SetText(labelText)
    label:SetWidth(60)
    label:SetJustifyH("LEFT")
    local buttons, prev = {}, label
    for _, e in ipairs(entries) do
        local b = CreateFrame("Button", nil, Frame, "BackdropTemplate")
        b:SetHeight(20)
        b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.label:SetPoint("CENTER")
        b.label:SetText(e.label)
        b:SetWidth(math.max(50, (tonumber(b.label:GetStringWidth()) or 40) + 20))
        b:SetPoint("LEFT", prev, "RIGHT", prev == label and 4 or -1, 0)
        b:SetScript("OnClick", function() setter(e.key); Rebuild() end)
        b.key = e.key
        table.insert(buttons, b)
        prev = b
    end
    local function Paint()
        for _, b in ipairs(buttons) do
            local on = getter() == b.key
            local seg = Theme and Theme.Current().roles.segment
            if seg and b.SetBackdrop then
                b:SetBackdrop(seg.backdrop)
                b:SetBackdropColor(unpack(on and Theme.Color("accentFill") or seg.bg))
                b:SetBackdropBorderColor(unpack(on and Theme.Color("accent") or seg.border))
            end
            local c = Theme and Theme.Color(on and "accent" or "textMid") or (on and { 1, 0.82, 0, 1 } or { 0.8, 0.8, 0.8, 1 })
            b.label:SetTextColor(unpack(c))
        end
    end
    return label, Paint
end

local kindLabel, PaintKinds = ToggleRow(title, L["EXPORT_WHAT"], {
    { key = "collect",  label = L["EXPORT_KIND_COLLECT"] },
    { key = "stock",    label = L["EXPORT_KIND_STOCK"] },
    { key = "tx",       label = L["EXPORT_KIND_TX"] },
    { key = "balances", label = L["EXPORT_KIND_BALANCES"] },
}, function() return state.kind end, function(k) state.kind = k end, -14)

local formatLabel, PaintFormats = ToggleRow(kindLabel, L["EXPORT_HOW"], {
    { key = "discord", label = L["EXPORT_FORMAT_DISCORD"] },
    { key = "csv",     label = L["EXPORT_FORMAT_CSV"] },
    { key = "text",    label = L["EXPORT_FORMAT_TEXT"] },
}, function() return state.format end, function(f) state.format = f end, -12)

-- Teile blaettern (nur Discord)
local prevBtn = CreateFrame("Button", nil, Frame, "UIPanelButtonTemplate")
prevBtn:SetSize(26, 20)
prevBtn:SetPoint("TOPRIGHT", Frame, "TOPRIGHT", -120, -76)
prevBtn:SetText("<")
local nextBtn = CreateFrame("Button", nil, Frame, "UIPanelButtonTemplate")
nextBtn:SetSize(26, 20)
nextBtn:SetPoint("LEFT", prevBtn, "RIGHT", 64, 0)
nextBtn:SetText(">")
local partText = Frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
partText:SetPoint("LEFT", prevBtn, "RIGHT", 4, 0)
partText:SetPoint("RIGHT", nextBtn, "LEFT", -4, 0)
if Theme then Theme.SkinButton(prevBtn); Theme.SkinButton(nextBtn) end

local explain = Frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
explain:SetPoint("TOPLEFT", formatLabel, "BOTTOMLEFT", 0, -10)
explain:SetPoint("RIGHT", Frame, "RIGHT", -24, 0)
explain:SetJustifyH("LEFT")

-- Textfeld
local scroll = CreateFrame("ScrollFrame", "GrindkeepExportScroll", Frame, "UIPanelScrollFrameTemplate")
scroll:SetPoint("TOPLEFT", explain, "BOTTOMLEFT", 2, -10)
scroll:SetPoint("BOTTOMRIGHT", Frame, "BOTTOMRIGHT", -40, 48)

local scrollBg = CreateFrame("Frame", nil, Frame, "BackdropTemplate")
scrollBg:SetPoint("TOPLEFT", scroll, "TOPLEFT", -6, 6)
scrollBg:SetPoint("BOTTOMRIGHT", scroll, "BOTTOMRIGHT", 26, -6)
scrollBg:SetFrameLevel(math.max(0, (Frame:GetFrameLevel() or 1)))
if Theme then Theme.Skin(scrollBg, "input") end

local editBox = CreateFrame("EditBox", nil, scroll)
editBox:SetMultiLine(true)
editBox:SetFontObject(ChatFontNormal)
editBox:SetWidth(560)
editBox:SetAutoFocus(false)
editBox:SetMaxLetters(0)
editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); Frame:Hide() end)
-- Das Feld ist nur zum Kopieren: Aenderungen werden verworfen
editBox:SetScript("OnTextChanged", function(self, userInput)
    if userInput then
        self:SetText(state.chunks[state.part] or "")
        self:HighlightText()
    end
end)
editBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
scroll:SetScrollChild(editBox)
scroll:SetScript("OnSizeChanged", function(self, w) if w and w > 0 then editBox:SetWidth(w) end end)

local copyHint = Frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
copyHint:SetPoint("BOTTOMLEFT", 24, 22)
copyHint:SetText(L["EXPORT_COPY_HINT"])

local charCount = Frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
charCount:SetPoint("BOTTOMRIGHT", -26, 22)

local function ShowPart()
    local n = #state.chunks
    state.part = math.max(1, math.min(state.part, n))
    local text = state.chunks[state.part] or ""
    editBox:SetText(text)
    editBox:SetCursorPosition(0)
    editBox:HighlightText()
    editBox:SetFocus()
    charCount:SetText(string.format(L["EXPORT_CHARS"], #text))
    local multi = state.format == "discord" and n > 1
    prevBtn:SetShown(multi); nextBtn:SetShown(multi); partText:SetShown(multi)
    partText:SetText(string.format(L["EXPORT_PART"], state.part, n))
    prevBtn:SetEnabled(state.part > 1)
    nextBtn:SetEnabled(state.part < n)
end
prevBtn:SetScript("OnClick", function() state.part = state.part - 1; ShowPart() end)
nextBtn:SetScript("OnClick", function() state.part = state.part + 1; ShowPart() end)

local EXPLAIN = { discord = "EXPORT_EXPLAIN_DISCORD", csv = "EXPORT_EXPLAIN_CSV", text = "EXPORT_EXPLAIN_TEXT" }

Rebuild = function()
    PaintKinds(); PaintFormats()
    explain:SetText(L[EXPLAIN[state.format]])
    local ok, chunks = pcall(Export.Build, state.kind, state.format)
    state.chunks = (ok and type(chunks) == "table" and #chunks > 0) and chunks or { L["EXPORT_FAILED"] }
    state.part = 1
    ShowPart()
end

if Theme then Theme.OnChange(function() if Frame:IsShown() then PaintKinds(); PaintFormats() end end) end

_G.GrindkeepExportUI = {
    Frame = Frame,
    Show = function(kind, format)
        if kind and Sources[kind] then state.kind = kind end
        if format then state.format = format end
        Frame:Show()
        Rebuild()
    end,
    Toggle = function()
        if Frame:IsShown() then Frame:Hide() else Frame:Show(); Rebuild() end
    end,
    CurrentText = function() return state.chunks[state.part] end,
    PartCount = function() return #state.chunks end,
    NextPart = function() state.part = state.part + 1; ShowPart() end,
}

if _G.GrindkeepStyle then _G.GrindkeepStyle.RegisterAndApply(Frame) end

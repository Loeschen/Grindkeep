--[[
    Grindkeep - UI.lua
    Dark-Slate Interface zur Auswertung der Gildenbank-Transaktionen.
    Reiner Konsument von GrindkeepDatabase (GetPlayerList/-Details/
    -Transactions) - keine Aenderung an Database.lua/Core.lua noetig.

    ================================================================
    MODERNISIERUNG (dieser Durchgang) - was ersetzt wurde und warum:
    ================================================================

    1) Scroll-System: die alte selbstgebaute Scrollbar + das manuelle
       Zeilen-Pooling sind komplett raus. Stattdessen:
       - CreateScrollBoxListLinearView() fuer das Zeilenlayout,
       - ScrollUtil.InitScrollBoxListWithScrollBar() zur Kopplung von
         ScrollBox und ScrollBar (uebernimmt Mausrad, Scroll-Inertia,
         automatisches Ein-/Ausblenden der Bar, Thumb-Groesse),
       - CreateDataProvider()/ScrollBox:SetDataProvider() zum Binden der
         Datensaetze,
       - das Recycling der Zeilen-Frames (= das, wofuer wir vorher einen
         eigenen Objekt-Pool gebaut hatten) uebernimmt jetzt die
         ScrollBox selbst.

    2) Kontextmenue: UIDropDownMenu/eigene Button-Frames sind raus,
       stattdessen MenuUtil.CreateContextMenu(owner, generator) mit
       rootDescription:CreateTitle()/:CreateButton(). Das ist Blizzards
       eigener, kampf-/taint-sicherer Menu-Stack - schliesst sich auch
       automatisch bei Klick daneben, ein eigener "Klick-Faenger" wie in
       der vorherigen Fassung ist damit ueberfluessig.

    3) Twink-Zuweisung: das hangebaute EditBox-Popup ist durch einen
       nativen StaticPopupDialogs-Eintrag (hasEditBox = true) ersetzt -
       das ist der Blizzard-Standardweg fuer "Bestaetigen + Text
       eingeben" und war im Original-Auftrag als "Dialog fuer SetAlt"
       ohnehin gefordert.

    EHRLICHER HINWEIS zur Verlässlichkeit dieses Refactors: Die exakten
    Signaturen von ScrollUtil/CreateScrollBoxListLinearView/ForEachFrame
    sind seit Dragonflight recht stabil, aber ich kann sie hier nicht
    gegen den echten WoW-Forever-Client pruefen. Eine bewusste
    Abweichung vom Auftragstext: ich nutze view:SetElementFactory(...)
    statt view:SetElementInitializer("TemplateName", ...), weil
    Letzteres einen per XML registrierten Template-Namen braucht - und
    dieses Addon ist seit Beginn bewusst XML-frei gehalten (siehe
    Kommentar unten bei den Zeilen-Initializern). SetElementFactory ist
    der dafuer vorgesehene, ebenfalls native Weg, Zeilen rein in Lua zu
    erzeugen. Sollte beim ersten Laden ein Lua-Fehler zu genau dieser
    Stelle auftreten, ist das der wahrscheinlichste Kandidat fuer eine
    Signatur-Abweichung in Forever - bitte den Fehlertext schicken,
    dann korrigiere ich gezielt nach.

    ================================================================
    OPTISCHE ANPASSUNG (dieser Durchgang) - Inspiration, kein Kopieren
    ================================================================
    Auf Wunsch als optische Frischzellenkur, inspiriert von Beute-/GDKP-
    Addons wie Gargul (nur der VISUELLE STIL wurde als Anregung genommen -
    keine Zeile Code, kein Icon/Font/Sound daraus wurde uebernommen, alles
    unten ist eigene Implementierung):
    - Das Fenster nutzt jetzt Blizzards eigenes, natives dunkles Dialog-
      Backdrop (_G.BACKDROP_DARK_DIALOG_32_32, z.B. auch vom Encounter
      Journal genutzt) statt der bisherigen flachen Eigenbau-Farbflaeche -
      mit Fallback auf das alte Backdrop, falls dieser Blizzard-Global in
      WoW Forever fehlen sollte (dieselbe defensive Haltung wie bei den
      C_Item-Kompat-Wrappern).
    - Eine erweiterte Statusfarben-Palette (Warnung/Hinweis) ergaenzt
      Gruen/Rot - bewusst eigene Flat-UI-Toene (Carrot/Sunflower), nicht
      Garguls konkrete Hex-Werte.
    - Dezentes Wasserzeichen unten links (Addon-Name + Version aus der
      .toc, nicht hart verdrahtet).
    - Minimieren-Button neben Schliessen: klappt den Fenster-Koerper ein,
      ohne das Fenster ganz zu schliessen.
]]

local DB = _G.GrindkeepDatabase
local L = _G.GrindkeepLocale
local Theme = _G.GrindkeepTheme

-- ============================================================
-- Farbpalette
-- ============================================================
local C = {
    bg        = { 18/255, 18/255, 22/255, 0.92 },
    panelBg   = { 24/255, 24/255, 29/255, 0.95 },
    border    = { 0x2a/255, 0x2d/255, 0x34/255, 1 },
    rowHover  = { 1, 1, 1, 0.05 },
    rowSelect = { 0xc9/255, 0xa2/255, 0x27/255, 0.12 },
    selectBorder = { 0xc9/255, 0xa2/255, 0x27/255, 1 },
    green     = { 0x2e/255, 0xcc/255, 0x71/255, 1 },
    red       = { 0xe7/255, 0x4c/255, 0x3c/255, 1 },
    -- Erweiterte Statusfarben (Warnung/Hinweis) - eigene Flat-UI-Toene
    -- (Carrot/Sunflower), passend zum bestehenden Gruen/Rot (Emerald/
    -- Alizarin), aber bewusst NICHT Garguls konkrete Hex-Werte.
    warning   = { 0xe6/255, 0x7e/255, 0x22/255, 1 },
    notice    = { 0xf1/255, 0xc4/255, 0x0f/255, 1 },
    textBright= { 0.92, 0.92, 0.95, 1 },
    textDim   = { 0.55, 0.55, 0.6, 1 },
}

local ROW_HEIGHT = 34
local EDGE = 13            -- Innenabstand zum nativen Fensterrahmen (siehe ApplyWindowBackdrop)
local WATERMARK_HEIGHT = 16 -- reservierter Streifen unten fuer das Wasserzeichen
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}

-- ============================================================
-- Hilfsfunktionen (unveraendert - CreateFrame mit BackdropTemplate ist
-- keine veraltete API, sondern der aktuelle Standardweg fuer Panels)
-- ============================================================
local function Backdrop(frame, bgColor, borderColor)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(unpack(bgColor or C.panelBg))
    frame:SetBackdropBorderColor(unpack(borderColor or C.border))
end

-- Aeusseres Fenster-Backdrop: Blizzards eigenes dunkles Dialog-Skin
-- (derselbe native Global, den z.B. auch das Encounter Journal nutzt),
-- statt der bisherigen flachen Eigenbau-Farbflaeche. Fallback auf das
-- alte Backdrop, falls dieser Global in WoW Forever fehlen/umbenannt
-- sein sollte - dieselbe defensive Haltung wie bei den C_Item-Wrappern.
local function ApplyWindowBackdrop(frame)
    if _G.BACKDROP_DARK_DIALOG_32_32 then
        frame:SetBackdrop(_G.BACKDROP_DARK_DIALOG_32_32)
    else
        frame:SetBackdrop(BACKDROP)
        frame:SetBackdropColor(unpack(C.bg))
        frame:SetBackdropBorderColor(unpack(C.border))
    end
end

-- Addon-Version aus der .toc lesen (kein hart verdrahteter String im
-- Wasserzeichen) - auch hier derselbe Kompat-Wrapper-Stil wie sonst im
-- Addon: C_AddOns.GetAddOnMetadata ist der neue, GetAddOnMetadata der
-- alte (aber ggf. noch vorhandene) Name.
local function GetAddonVersion()
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not getter then return "?" end
    local ok, version = pcall(getter, "Grindkeep", "Version")
    if ok and version then return version end
    return "?"
end

local function NewFrame(parent, template)
    return CreateFrame("Frame", nil, parent, template or "BackdropTemplate")
end

local function FormatRelative(ts)
    local diff = time() - (ts or time())
    if diff < 60 then
        return L["UI_RELATIVE_JUSTNOW"]
    elseif diff < 3600 then
        return math.floor(diff / 60) .. L["UI_RELATIVE_MIN"]
    elseif diff < 86400 then
        return math.floor(diff / 3600) .. L["UI_RELATIVE_HOUR"]
    else
        return math.floor(diff / 86400) .. L["UI_RELATIVE_DAY"]
    end
end

-- "vor 3 Std." bzw. "gerade eben" (ohne das doppelte "vor gerade eben")
local function Ago(ts)
    local diff = time() - (ts or time())
    if diff < 60 then return L["UI_RELATIVE_JUSTNOW"] end
    return string.format(L["UI_TIME_AGO"], FormatRelative(ts))
end

-- ---------- Roster-Cache nur fuer die Klassenfarbe (Praesentation) ----------
-- Die Gildenbank-API liefert keine Klasse zu einem Log-Eintrag; das
-- holen wir best-effort separat aus dem Gildenroster.
local rosterClassByName = {}

-- Anfordern und Auslesen sind getrennt: GuildRoster() loest selbst
-- GUILD_ROSTER_UPDATE aus. Wuerde der Event-Handler erneut anfordern,
-- entstuende eine Endlosschleife von Roster-Anfragen.
local function RequestRoster()
    if not IsInGuild or not IsInGuild() then return end
    pcall(function()
        if C_GuildInfo and C_GuildInfo.GuildRoster then
            C_GuildInfo.GuildRoster()
        elseif GuildRoster then
            GuildRoster()
        end
    end)
end

local function ReadRoster()
    if not IsInGuild or not IsInGuild() then return end
    pcall(function()
        local num = GetNumGuildMembers and GetNumGuildMembers() or 0
        for i = 1, num do
            local fullName, _, _, _, _, _, _, _, _, _, classFileName = GetGuildRosterInfo(i)
            if fullName then
                local shortName = fullName:match("^([^-]+)") or fullName
                rosterClassByName[shortName] = classFileName
            end
        end
    end)
end

local function ClassColor(name)
    local class = rosterClassByName[name]
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return c.r, c.g, c.b end
    return 0.8, 0.8, 0.8
end

-- Kompatibilitaets-Wrapper: der In-Game-Test hat gezeigt, dass das
-- alte globale GetItemInfo() in WoW Forever entfernt wurde - nur noch
-- C_Item.* existiert. Dieselbe Migration betrifft vermutlich auch
-- GetItemIcon(), daher hier vorsorglich dieselbe Absicherung wie in
-- Core.lua fuer GetItemInfoCompat.
local function GetItemIconCompat(itemID)
    if C_Item and C_Item.GetItemIconByID then
        return C_Item.GetItemIconByID(itemID)
    elseif GetItemIcon then
        return GetItemIcon(itemID)
    end
    return nil
end

-- ============================================================
-- Kontextmenue ueber MenuUtil (ersetzt UIDropDownMenu + eigenes
-- Popup-Frame komplett - kein Klick-Faenger mehr noetig, das
-- schliesst Blizzards Menu-Stack selbst)
-- ============================================================
local ShowTwinkAssignPopup -- Vorwaertsdeklaration, wird unten (StaticPopup) definiert

local function PostReport(playerName, channel)
    local details = DB.GetPlayerDetails(playerName)
    if not details then return end
    local agg = details.aggregated
    local net = agg.goldDeposited - agg.goldWithdrawn
    -- Nur reiner Text: Muenz-Symbole (Textur-Codes) lehnt der Chat ab.
    local abs = math.abs(net)
    local goldText = string.format("%dg %ds %dc", math.floor(abs / 10000), math.floor(abs / 100) % 100, abs % 100)
    local msg = string.format(L["UI_REPORT_LINE"],
        playerName, net < 0 and "-" or "", goldText,
        agg.itemDeposits, agg.itemWithdrawals)
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local ok = send and pcall(send, msg, channel)
    if not ok then
        print("|cffe74c3c[Grindkeep]|r " .. L["UI_REPORT_SEND_FAILED"])
    end
end

-- Fluestern ueber Blizzards eigene Funktion statt "/w Name": die kommt
-- auch mit Namen aus Vor- und Nachname zurecht (WoW Forever).
local function WhisperPlayer(playerName)
    local sendTell = (ChatFrameUtil and ChatFrameUtil.SendTell) or ChatFrame_SendTell
    if sendTell then
        pcall(sendTell, playerName, DEFAULT_CHAT_FRAME)
        return
    end
    local openChat = (ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat
    if openChat then pcall(openChat, "/w " .. playerName .. " ", DEFAULT_CHAT_FRAME) end
end

local function ShowPlayerContextMenu(playerName, ownerRegion)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        -- Ohne Blizzards Menue-System bleibt der wichtigste Eintrag erreichbar.
        ShowTwinkAssignPopup(playerName)
        return
    end
    MenuUtil.CreateContextMenu(ownerRegion, function(owner, rootDescription)
        rootDescription:CreateTitle(playerName)

        rootDescription:CreateButton(L["UI_CTX_WHISPER"], function()
            WhisperPlayer(playerName)
        end)

        rootDescription:CreateButton(L["UI_CTX_INVITE"], function()
            local ok = pcall(function()
                if C_PartyInfo and C_PartyInfo.InviteUnit then
                    C_PartyInfo.InviteUnit(playerName)
                elseif InviteUnit then
                    InviteUnit(playerName)
                elseif InviteByName then
                    InviteByName(playerName)
                end
            end)
            if not ok then
                print("|cffe74c3c[Grindkeep]|r " .. L["UI_CTX_INVITE_FAILED"])
            end
        end)

        -- Untermenue: CreateButton() ohne eigenen Klick-Callback liefert
        -- eine verschachtelbare Description zurueck, auf der wir selbst
        -- wieder :CreateButton() aufrufen koennen.
        local reportMenu = rootDescription:CreateButton(L["UI_CTX_REPORT"])
        reportMenu:CreateButton(L["UI_CTX_REPORT_GUILD"], function() PostReport(playerName, "GUILD") end)
        reportMenu:CreateButton(L["UI_CTX_REPORT_OFFICER"], function() PostReport(playerName, "OFFICER") end)

        rootDescription:CreateButton(L["UI_CTX_ASSIGN_TWINK"], function()
            ShowTwinkAssignPopup(playerName)
        end)

        local g = DB.GetGuildData()
        if g and g.alts[playerName] then
            rootDescription:CreateButton(L["UI_CTX_UNASSIGN_TWINK"], function()
                if DB.ClearAlt(playerName) then
                    print("|cff2ecc71[Grindkeep]|r " .. string.format(L["CORE_ALT_CLEARED"], playerName))
                    if _G.GrindkeepComm and _G.GrindkeepComm.BroadcastAltRemoval then
                        _G.GrindkeepComm.BroadcastAltRemoval(playerName)
                    end
                    if _G.GrindkeepUI then _G.GrindkeepUI.Refresh() end
                end
            end)
        end

        rootDescription:CreateButton(L["UI_CTX_SEARCH_PLAYER"], function()
            if _G.GrindkeepSearchUI then _G.GrindkeepSearchUI.ShowForPlayer(playerName) end
        end)
    end)
end

-- ============================================================
-- Twink-Zuweisung ueber einen nativen StaticPopup (ersetzt das
-- handgebaute EditBox-Popup-Frame)
-- ============================================================
-- Das Eingabefeld des Popups heisst je nach Client "editBox" (alt) oder
-- "EditBox" (neu, u.a. WoW Forever und Retail ab 11.2). Genau daran ist
-- dieser Dialog frueher auf Forever abgestuerzt.
local function PopupEditBox(popup)
    if not popup then return nil end
    return popup.EditBox or popup.editBox or (popup.GetEditBox and popup:GetEditBox())
end

local function AcceptTwinkAssignment(popup)
    local eb = PopupEditBox(popup)
    local mainName = eb and eb:GetText()
    local twinkName = popup and popup.data
    if not twinkName or not mainName then return end
    mainName = mainName:gsub("^%s+", ""):gsub("%s+$", "")
    if mainName == "" then return end
    if DB.SetAlt(twinkName, mainName) then
        local root = DB.GetMain(twinkName)
        print("|cff2ecc71[Grindkeep]|r " .. string.format(L["UI_TWINK_ASSIGNED"], twinkName, root))
        if _G.GrindkeepComm then _G.GrindkeepComm.BroadcastAltAssignment(twinkName, root) end
        if _G.GrindkeepUI then _G.GrindkeepUI.Refresh() end
    else
        print("|cffe74c3c[Grindkeep]|r " .. L["CORE_ALT_USAGE"])
    end
end

StaticPopupDialogs["GRINDKEEP_ASSIGN_TWINK"] = {
    text = L["UI_ASSIGN_TWINK_POPUP_TEXT"],
    button1 = OKAY,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 64, -- "Vorname Nachname-Realm" passt sonst nicht hinein
    OnShow = function(self)
        local eb = PopupEditBox(self)
        if eb then
            eb.gkPopup = self
            eb:SetText("")
            eb:SetFocus()
        end
    end,
    OnAccept = function(self)
        AcceptTwinkAssignment(self)
    end,
    EditBoxOnEnterPressed = function(self)
        local popup = self.gkPopup or self:GetParent()
        AcceptTwinkAssignment(popup)
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

ShowTwinkAssignPopup = function(playerName)
    StaticPopup_Show("GRINDKEEP_ASSIGN_TWINK", playerName, nil, playerName)
end

-- ============================================================
-- Hauptfenster (seit 1.1: ein Fenster mit Reitern)
--
-- Von oben nach unten:
--   Kopfzeile    Titel + Gildenname, rechts Hilfe, Minimieren, Schliessen
--   Reiterzeile  Uebersicht | Mitglieder | Vorgaenge | Bestand | (Loot)
--   Leiste       Zeitraum (nur wo er gilt) und Stand des Bank-Logs
--   Inhalt       die gewaehlte Seite
--
-- Vorgaenge, Bestand und Loot waren frueher eigene Fenster, die sich
-- gegenseitig verdeckten. Sie werden jetzt als Seiten eingebettet (siehe
-- Style.EmbedFrame); ihr Code bleibt in Search.lua, Stock.lua, Loot.lua.
-- Den frueheren gruen-roten Balken gibt es nicht mehr: er war ohne
-- Beschriftung nicht zu verstehen. Stattdessen stehen die Zahlen da.
-- ============================================================
local DEFAULT_WIDTH, DEFAULT_HEIGHT = 820, 540
local MIN_WIDTH, MIN_HEIGHT = 660, 400
local MAX_WIDTH, MAX_HEIGHT = 1600, 1000
local HEADER_HEIGHT, TABBAR_HEIGHT, SUBBAR_HEIGHT = 34, 28, 28
local CARD_HEIGHT = 58
local GAP = 8
local MEMBER_ROW_HEIGHT = 40
local TX_ROW_HEIGHT = 36
local LEFT_WIDTH = 250
local TOP_WIDTH = 230

C.cardBg     = { 30 / 255, 30 / 255, 37 / 255, 0.95 }
C.segBg      = { 1, 1, 1, 0.04 }
C.accentFill = { 0xc9 / 255, 0xa2 / 255, 0x27 / 255, 0.22 }
C.neutral    = { 0.8, 0.8, 0.85, 1 }
C.textMid    = { 0.75, 0.75, 0.8, 1 }

-- ---------- Zahlen ----------
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t"

local function Thousands(n)
    if BreakUpLargeNumbers then
        local ok, s = pcall(BreakUpLargeNumbers, n)
        if ok and type(s) == "string" then return s end
    end
    local s = tostring(n)
    local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
    return (out:gsub("^%.", ""))
end

-- Kurzform fuer Karten und Listen: ab 1 Gold nur volle Goldstuecke,
-- darunter Silber/Kupfer. Der genaue Betrag steht im Tooltip.
local function MoneyShort(copper)
    copper = math.abs(math.floor(copper or 0))
    if copper == 0 then return "0" .. GOLD_ICON end
    if copper >= 10000 then return Thousands(math.floor(copper / 10000)) .. GOLD_ICON end
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return tostring(copper) .. "c"
end

local function MoneyExact(copper)
    copper = math.abs(math.floor(copper or 0))
    if GetCoinTextureString then return GetCoinTextureString(copper) end
    return tostring(copper) .. "c"
end

local function SignedMoney(copper)
    copper = copper or 0
    if copper > 0 then return "+" .. MoneyShort(copper) end
    if copper < 0 then return "-" .. MoneyShort(-copper) end
    return MoneyShort(0)
end

local function NetColor(copper)
    if (copper or 0) > 0 then return C.green end
    if (copper or 0) < 0 then return C.red end
    return C.neutral
end

-- ---------- Fenster ----------
local MainFrame = CreateFrame("Frame", "GrindkeepMainFrame", UIParent, "BackdropTemplate")
tinsert(UISpecialFrames, "GrindkeepMainFrame") -- mit Escape schliessbar
MainFrame:SetSize(DEFAULT_WIDTH, DEFAULT_HEIGHT)
MainFrame:SetPoint("CENTER")
MainFrame:SetFrameStrata("HIGH")
MainFrame:SetMovable(true)
MainFrame:EnableMouse(true)
MainFrame:RegisterForDrag("LeftButton")
MainFrame:SetScript("OnDragStart", MainFrame.StartMoving)
MainFrame:SetScript("OnDragStop", MainFrame.StopMovingOrSizing)
Theme.Skin(MainFrame, "window")
MainFrame:Hide()

local EXPANDED_HEIGHT = DEFAULT_HEIGHT
local isMinimized = false

-- Groesse per Shift + linke Maustaste ziehen (an jeder Stelle des
-- Fensters); ohne Shift wird verschoben. Die Groesse wird gespeichert.
MainFrame:SetResizable(true)
if MainFrame.SetResizeBounds then
    MainFrame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
else
    if MainFrame.SetMinResize then MainFrame:SetMinResize(MIN_WIDTH, MIN_HEIGHT) end
    if MainFrame.SetMaxResize then MainFrame:SetMaxResize(MAX_WIDTH, MAX_HEIGHT) end
end

local function SaveWindowSize()
    if isMinimized then return end
    local w, h = MainFrame:GetWidth(), MainFrame:GetHeight()
    if not w or not h then return end
    EXPANDED_HEIGHT = h
    if DB and DB.SetSetting then
        DB.SetSetting("windowWidth", math.floor(w + 0.5))
        DB.SetSetting("windowHeight", math.floor(h + 0.5))
    end
end

local function StartResizing()
    if isMinimized then return end
    MainFrame:StartSizing("BOTTOMRIGHT")
end

local function StopResizing()
    MainFrame:StopMovingOrSizing()
    SaveWindowSize()
end

MainFrame:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" and IsShiftKeyDown() then StartResizing() end
end)
MainFrame:SetScript("OnMouseUp", function(_, button)
    if button == "LeftButton" then StopResizing() end
end)

local function RestoreWindowSize()
    local savedW = DB.GetSetting("windowWidth")
    local savedH = DB.GetSetting("windowHeight")
    if type(savedW) == "number" and type(savedH) == "number" then
        savedW = math.max(MIN_WIDTH, math.min(MAX_WIDTH, savedW))
        savedH = math.max(MIN_HEIGHT, math.min(MAX_HEIGHT, savedH))
        MainFrame:SetSize(savedW, savedH)
        EXPANDED_HEIGHT = savedH
    end
end

-- ---------- Bausteine ----------
-- color: Name einer Designfarbe ("textDim", "title", ...) oder { r, g, b }
local function Text(parent, template, color)
    local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
    if type(color) == "string" then
        Theme.TextColor(fs, color)
    elseif color then
        fs:SetTextColor(unpack(color))
    end
    return fs
end

local function SimpleTooltip(frame, textFn)
    frame:SetScript("OnEnter", function(self)
        local t = textFn(self)
        if not t or t == "" then return end
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(t, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- Kennzahl-Kachel: kleine Beschriftung oben, grosser Wert unten.
local function MakeCard(parent, labelText, height)
    local card = NewFrame(parent)
    Theme.Skin(card, "card")
    card:SetHeight(height or CARD_HEIGHT)
    card.label = Text(card, "GameFontDisableSmall", "textDim")
    card.label:SetPoint("TOPLEFT", 10, -8)
    card.label:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.label:SetJustifyH("LEFT")
    card.label:SetText(labelText)
    card.value = Text(card, "GameFontHighlightLarge")
    card.value:SetPoint("BOTTOMLEFT", 10, 9)
    card.value:SetPoint("RIGHT", card, "RIGHT", -8, 0)
    card.value:SetJustifyH("LEFT")
    card.value:SetWordWrap(false)
    card:EnableMouse(true)
    SimpleTooltip(card, function(self) return self.tooltip end)
    return card
end

-- Kacheln einer Reihe gleichmaessig auf die Breite verteilen.
local function CardRow(parent, cards, height)
    local row = CreateFrame("Frame", nil, parent)
    row:SetHeight(height or CARD_HEIGHT)
    local function Layout()
        local w = tonumber(row:GetWidth()) or 0
        if w <= 0 then return end
        local cw = (w - GAP * (#cards - 1)) / #cards
        for i, card in ipairs(cards) do
            card:SetParent(row)
            card:ClearAllPoints()
            card:SetPoint("TOPLEFT", row, "TOPLEFT", (i - 1) * (cw + GAP), 0)
            card:SetWidth(cw)
        end
    end
    row:SetScript("OnSizeChanged", Layout)
    row.Layout = Layout
    return row
end

-- Umschalter aus mehreren Feldern ("Alles | 7 Tage | ...").
local function MakeSegments(parent, entries, onSelect)
    local holder = CreateFrame("Frame", nil, parent)
    holder:SetHeight(20)
    holder.buttons = {}
    local prev, total = nil, 0
    for _, e in ipairs(entries) do
        local b = CreateFrame("Button", nil, holder, "BackdropTemplate")
        b:SetHeight(20)
        b.label = Text(b, "GameFontHighlightSmall")
        b.label:SetPoint("CENTER")
        b.label:SetText(e.label)
        local w = math.max(38, (tonumber(b.label:GetStringWidth()) or 30) + 18)
        b:SetWidth(w)
        total = total + w - (prev and 1 or 0)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", -1, 0)
        else
            b:SetPoint("LEFT", holder, "LEFT", 0, 0)
        end
        b:SetScript("OnClick", function() onSelect(e.key) end)
        if e.tooltip then SimpleTooltip(b, function() return e.tooltip end) end
        holder.buttons[e.key] = b
        prev = b
    end
    holder:SetWidth(total)
    function holder:SetActive(key)
        for k, b in pairs(self.buttons) do
            local seg = Theme.Current().roles.segment
            b:SetBackdrop(seg.backdrop)
            if k == key then
                b:SetBackdropColor(unpack(Theme.Color("accentFill")))
                b:SetBackdropBorderColor(unpack(Theme.Color("accent")))
                b.label:SetTextColor(unpack(Theme.Color("accent")))
            else
                b:SetBackdropColor(unpack(seg.bg))
                b:SetBackdropBorderColor(unpack(seg.border))
                b.label:SetTextColor(unpack(Theme.Color("textMid")))
            end
        end
        self.active = key
    end
    Theme.OnChange(function() if holder.active then holder:SetActive(holder.active) end end)
    return holder
end

-- ---------- Kopfzeile ----------
local header = NewFrame(MainFrame)
header:SetHeight(HEADER_HEIGHT)
header:SetPoint("TOPLEFT", EDGE, -EDGE)
header:SetPoint("TOPRIGHT", -EDGE, -EDGE)
header:EnableMouse(true)
header:RegisterForDrag("LeftButton")
header:SetScript("OnDragStart", function()
    if IsShiftKeyDown() then StartResizing() else MainFrame:StartMoving() end
end)
header:SetScript("OnDragStop", function()
    MainFrame:StopMovingOrSizing()
    SaveWindowSize()
end)

local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("LEFT", 8, 0)
title:SetText("Grindkeep")
Theme.TextColor(title, "title")

local guildText = Text(header, "GameFontHighlight", "textDim")
guildText:SetPoint("LEFT", title, "RIGHT", 10, -1)

local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
closeBtn:SetPoint("RIGHT", 0, 0)
closeBtn:SetScript("OnClick", function() MainFrame:Hide() end)
Theme.SkinClose(closeBtn)

local tabBar, subBar, content, watermark -- unten angelegt, vom Minimieren gebraucht

local minimizeBtn = CreateFrame("Button", nil, header)
minimizeBtn:SetSize(20, 20)
minimizeBtn:SetPoint("RIGHT", closeBtn, "LEFT", -2, 0)
local minimizeLabel = minimizeBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
minimizeLabel:SetAllPoints()
minimizeLabel:SetText("-")
Theme.TextColor(minimizeLabel, "textMid")
minimizeBtn:SetScript("OnClick", function()
    isMinimized = not isMinimized
    for _, f in ipairs({ tabBar, subBar, content }) do f:SetShown(not isMinimized) end
    watermark:SetShown(not isMinimized)
    if isMinimized then
        MainFrame:SetHeight(HEADER_HEIGHT + EDGE * 2)
        minimizeLabel:SetText("+")
    else
        MainFrame:SetHeight(EXPANDED_HEIGHT)
        minimizeLabel:SetText("-")
    end
end)

local helpBtn = CreateFrame("Button", nil, header, "UIPanelButtonTemplate")
helpBtn:SetSize(24, 22)
helpBtn:SetPoint("RIGHT", minimizeBtn, "LEFT", -8, 0)
helpBtn:SetText("?")
helpBtn:SetScript("OnClick", function()
    if _G.GrindkeepHelpUI then _G.GrindkeepHelpUI.Toggle() end
end)
SimpleTooltip(helpBtn, function() return L["HELP_BUTTON_TOOLTIP"] end)
Theme.SkinButton(helpBtn)

-- ---------- Zahnrad: Design, Akzentfarbe, Optionen ----------
local gearBtn = CreateFrame("Button", nil, header)
gearBtn:SetSize(22, 22)
gearBtn:SetPoint("RIGHT", helpBtn, "LEFT", -6, 0)
local gearIcon = gearBtn:CreateTexture(nil, "ARTWORK")
gearIcon:SetAllPoints()
-- Zahnrad-Grafik: moderne Atlas-Grafik, sonst die alte Datei, sonst das
-- Zahnrad-Symbol aus den Gegenstandsicons (gibt es in jeder Version).
local function SetGearTexture()
    if C_Texture and C_Texture.GetAtlasInfo and gearIcon.SetAtlas then
        local ok, info = pcall(C_Texture.GetAtlasInfo, "QuestLog-icon-setting")
        if ok and info then gearIcon:SetAtlas("QuestLog-icon-setting") return end
    end
    if GetFileIDFromPath then
        local ok, id = pcall(GetFileIDFromPath, "Interface\\Buttons\\UI-OptionsButton")
        if ok and id then gearIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton") return end
    end
    gearIcon:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    gearIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
end
SetGearTexture()
local gearHover = gearBtn:CreateTexture(nil, "HIGHLIGHT")
gearHover:SetAllPoints()
gearHover:SetColorTexture(1, 1, 1, 0.15)
SimpleTooltip(gearBtn, function() return L["MENU_GEAR_TOOLTIP"] end)

local function OpenAllOptions()
    if not (_G.GrindkeepOptions and _G.GrindkeepOptions.OpenToCategory and _G.GrindkeepOptions.OpenToCategory()) then
        print("|cffe74c3c[Grindkeep]|r " .. L["CORE_OPTIONS_UNAVAILABLE"])
    end
end

gearBtn:SetScript("OnClick", function(self)
    if not (MenuUtil and MenuUtil.CreateContextMenu) then
        -- Ohne Menue-System: Design der Reihe nach durchschalten
        local list, cur = Theme.List, Theme.Key()
        for i, k in ipairs(list) do
            if k == cur then Theme.Set(list[i % #list + 1]) break end
        end
        print("|cff2ecc71[Grindkeep]|r " .. string.format(L["THEME_SET"], L[Theme.Current().label]))
        return
    end
    MenuUtil.CreateContextMenu(self, function(_, root)
        root:CreateTitle(L["MENU_DESIGN"])
        for _, key in ipairs(Theme.List) do
            root:CreateRadio(L[Theme.Defs[key].label],
                function() return Theme.Key() == key end,
                function() Theme.Set(key) end)
        end
        local accent = root:CreateButton(L["MENU_ACCENT"])
        for _, a in ipairs(Theme.Accents) do
            accent:CreateRadio(L[a.label],
                function() return (DB.GetSetting("accent") or "theme") == a.key end,
                function() Theme.SetAccent(a.key) end)
        end
        root:CreateDivider()
        root:CreateButton(L["MENU_EXPORT"], function()
            if _G.GrindkeepExportUI then
                local kinds = { collect = "collect", stock = "stock", search = "tx", members = "balances", overview = "balances" }
                _G.GrindkeepExportUI.Show(kinds[_G.GrindkeepUI.ActiveTab()])
            end
        end)
        root:CreateButton(L["MENU_ALL_OPTIONS"], OpenAllOptions)
        root:CreateButton(L["MENU_HELP"], function()
            if _G.GrindkeepHelpUI then _G.GrindkeepHelpUI.Toggle() end
        end)
    end)
end)

guildText:SetPoint("RIGHT", gearBtn, "LEFT", -12, 0)
guildText:SetJustifyH("LEFT")
guildText:SetWordWrap(false)

-- ---------- Reiterzeile ----------
tabBar = CreateFrame("Frame", nil, MainFrame)
tabBar:SetHeight(TABBAR_HEIGHT)
tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -2)
tabBar:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -2)

local tabLine = tabBar:CreateTexture(nil, "ARTWORK")
Theme.Tint(tabLine, "line")
tabLine:SetHeight(1)
tabLine:SetPoint("BOTTOMLEFT")
tabLine:SetPoint("BOTTOMRIGHT")

local TABS = {
    { key = "overview", label = L["UI_TAB_OVERVIEW"] },
    { key = "members",  label = L["UI_TAB_MEMBERS"] },
    { key = "search",   label = L["UI_TAB_TRANSACTIONS"], module = "GrindkeepSearchUI" },
    { key = "stock",    label = L["UI_TAB_STOCK"],        module = "GrindkeepStockUI" },
    { key = "collect",  label = L["UI_TAB_COLLECT"],      module = "GrindkeepCollectUI" },
    { key = "loot",     label = L["UI_TAB_LOOT"],         module = "GrindkeepLootUI" },
}
-- Seiten, auf denen der Zeitraum eine Rolle spielt
local USES_PERIOD = { overview = true, members = true, search = true }

local tabButtons, pages = {}, {}
local activeTab = "overview"
local SelectTab -- Vorwaertsdeklaration

for _, t in ipairs(TABS) do
    local b = CreateFrame("Button", nil, tabBar)
    b:SetHeight(TABBAR_HEIGHT)
    b.label = Text(b, "GameFontNormal")
    b.label:SetPoint("CENTER", 0, 1)
    b.label:SetText(t.label)
    b:SetWidth((tonumber(b.label:GetStringWidth()) or 60) + 28)
    b.hover = b:CreateTexture(nil, "BACKGROUND")
    b.hover:SetAllPoints()
    Theme.Tint(b.hover, "rowHover")
    b.hover:Hide()
    b.underline = b:CreateTexture(nil, "OVERLAY")
    Theme.Tint(b.underline, "accent")
    b.underline:SetHeight(2)
    b.underline:SetPoint("BOTTOMLEFT", 6, 0)
    b.underline:SetPoint("BOTTOMRIGHT", -6, 0)
    b.underline:Hide()
    b:SetScript("OnEnter", function(self) self.hover:Show() end)
    b:SetScript("OnLeave", function(self) self.hover:Hide() end)
    b:SetScript("OnClick", function() SelectTab(t.key) end)
    tabButtons[t.key] = b
end

local function TabAvailable(key)
    if key == "loot" then
        return DB.GetSetting("lootTrackingEnabled") and pages.loot ~= nil
    end
    if key == "search" or key == "stock" or key == "collect" then return pages[key] ~= nil end
    return true
end

-- Reiter von links nach rechts anordnen; Loot nur bei eingeschalteter
-- Loot-Erfassung, eingebettete Seiten nur, wenn ihr Modul geladen ist.
local function LayoutTabs()
    local prev
    for _, t in ipairs(TABS) do
        local b = tabButtons[t.key]
        b:ClearAllPoints()
        if TabAvailable(t.key) then
            if prev then b:SetPoint("LEFT", prev, "RIGHT", 2, 0) else b:SetPoint("LEFT", tabBar, "LEFT", 0, 0) end
            b:Show()
            prev = b
        else
            b:Hide()
        end
    end
    if not TabAvailable(activeTab) and SelectTab and MainFrame:IsShown() then
        SelectTab("overview")
    end
end
-- Alter Name, wird noch von Options.lua aufgerufen
local LayoutHeaderButtons = LayoutTabs

-- ---------- Leiste: Zeitraum + Stand ----------
subBar = CreateFrame("Frame", nil, MainFrame)
subBar:SetHeight(SUBBAR_HEIGHT)
subBar:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -4)
subBar:SetPoint("TOPRIGHT", tabBar, "BOTTOMRIGHT", 0, -4)

local periodLabel = Text(subBar, "GameFontHighlightSmall", "textDim")
periodLabel:SetPoint("LEFT", 2, 0)
periodLabel:SetText(L["UI_PERIOD_LABEL"])

local periodDays = nil -- nil = gesamter Verlauf
local function PeriodSince()
    return periodDays and (DB.Now() - periodDays * 86400) or nil
end

local RefreshActive -- Vorwaertsdeklaration

local periodSeg
periodSeg = MakeSegments(subBar, {
    { key = "all", label = L["UI_PERIOD_ALL"], tooltip = L["UI_PERIOD_TOOLTIP"] },
    { key = "7",   label = L["UI_PERIOD_7"],   tooltip = L["UI_PERIOD_TOOLTIP"] },
    { key = "30",  label = L["UI_PERIOD_30"],  tooltip = L["UI_PERIOD_TOOLTIP"] },
    { key = "90",  label = L["UI_PERIOD_90"],  tooltip = L["UI_PERIOD_TOOLTIP"] },
}, function(key)
    periodDays = tonumber(key)
    periodSeg:SetActive(key)
    if _G.GrindkeepSearchUI and _G.GrindkeepSearchUI.SetPeriod then
        _G.GrindkeepSearchUI.SetPeriod(periodDays)
    end
    RefreshActive()
end)
periodSeg:SetPoint("LEFT", periodLabel, "RIGHT", 8, 0)
periodSeg:SetActive("all")

local statusText = Text(subBar, "GameFontHighlightSmall", "textDim")
statusText:SetPoint("RIGHT", subBar, "RIGHT", -4, 0)
statusText:SetPoint("LEFT", periodSeg, "RIGHT", 16, 0)
statusText:SetJustifyH("RIGHT")
statusText:SetWordWrap(false)

local function LastScanInfo()
    return DB.GetLastLogScan and DB.GetLastLogScan() or nil
end

local function RefreshStatus()
    local scan = LastScanInfo()
    if not scan then
        statusText:SetText("|cffe67e22" .. L["UI_STATUS_NEVER"] .. "|r")
        return
    end
    local tabs
    if (scan.tabs or 0) == 0 then
        tabs = L["UI_STATUS_NO_TABS"]
    elseif scan.tabs == 1 then
        tabs = L["UI_STATUS_TAB1"]
    else
        tabs = string.format(L["UI_STATUS_TABS"], scan.tabs)
    end
    statusText:SetText(string.format(L["UI_STATUS_READ"], Ago(scan.at)) .. "  ·  " .. tabs)
end

-- ---------- Inhalt ----------
watermark = MainFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
watermark:SetPoint("BOTTOMLEFT", EDGE + 4, EDGE + 2)
watermark:SetText("Grindkeep v" .. GetAddonVersion())
Theme.TextColor(watermark, "textDim")

content = CreateFrame("Frame", nil, MainFrame)
content:SetPoint("TOPLEFT", subBar, "BOTTOMLEFT", 0, -6)
content:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", -EDGE, EDGE + WATERMARK_HEIGHT)

local function NewPage()
    local p = CreateFrame("Frame", nil, content)
    p:SetAllPoints(content)
    p:Hide()
    return p
end

-- ---------- Zeilen fuer Vorgaenge (Uebersicht + Spielerdetails) ----------
local ACTION_KEYS = {
    move = "SEARCH_ACTION_MOVE",
    repair = "SEARCH_ACTION_REPAIR",
}

local function TxWhere(tx)
    if tx.kind == "gold" then return L["UI_GOLD_LOG_LABEL"] end
    return tx.tabName or string.format(L["UI_TAB_LABEL"], tostring(tx.tab or "?"))
end

-- Eine Zeile: Symbol | "Name  +20x Leinenstoff" | darunter "vor 2 Std. · Fach 1"
local function MakeTxRowInit(showPlayer)
    return function(button, tx)
        if not button.initialized then
            button.initialized = true
            button.hl = button:CreateTexture(nil, "BACKGROUND")
            button.hl:SetAllPoints()
            button.hl:Hide()

            button.icon = button:CreateTexture(nil, "ARTWORK")
            button.icon:SetSize(24, 24)
            button.icon:SetPoint("LEFT", 6, 0)

            button.iconBorder = CreateFrame("Frame", nil, button, "BackdropTemplate")
            button.iconBorder:SetPoint("TOPLEFT", button.icon, -1, 1)
            button.iconBorder:SetPoint("BOTTOMRIGHT", button.icon, 1, -1)
            button.iconBorder:SetBackdrop({ edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })

            button.line = Text(button, "GameFontHighlightSmall")
            button.line:SetPoint("TOPLEFT", button.icon, "TOPRIGHT", 8, 1)
            button.line:SetPoint("RIGHT", button, "RIGHT", -8, 0)
            button.line:SetJustifyH("LEFT")
            button.line:SetWordWrap(false)

            button.sub = Text(button, "GameFontDisableSmall", "textDim")
            button.sub:SetPoint("BOTTOMLEFT", button.icon, "BOTTOMRIGHT", 8, -1)
            button.sub:SetPoint("RIGHT", button, "RIGHT", -8, 0)
            button.sub:SetJustifyH("LEFT")
            button.sub:SetWordWrap(false)

            button:EnableMouse(true)
            button:SetScript("OnEnter", function(self)
                self.hl:Show()
                if self.itemLink then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    pcall(GameTooltip.SetHyperlink, GameTooltip, self.itemLink)
                    GameTooltip:Show()
                elseif self.exactMoney then
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.exactMoney, 1, 1, 1)
                    GameTooltip:Show()
                end
            end)
            button:SetScript("OnLeave", function(self)
                self.hl:Hide()
                GameTooltip:Hide()
            end)
            if _G.GrindkeepStyle then _G.GrindkeepStyle.ApplyToFrame(button) end
        end

        button.hl:SetColorTexture(unpack(Theme.Color("rowHover")))
        local action = tx.action == "withdrawal" and "withdraw" or tx.action
        local color, sign = C.neutral, ""
        if action == "deposit" then color, sign = C.green, "+"
        elseif action == "withdraw" then color, sign = C.red, "-" end
        local verb = ACTION_KEYS[action] and (L[ACTION_KEYS[action]] .. " ") or ""

        local what
        if tx.kind == "gold" then
            button.icon:SetTexture(133784) -- Muenzen
            button.iconBorder:Hide()
            button.itemLink = nil
            button.exactMoney = MoneyExact(tx.amount)
            what = sign .. MoneyExact(tx.amount)
        else
            button.icon:SetTexture((tx.itemID and GetItemIconCompat(tx.itemID)) or 134400)
            local q = (tx.itemQuality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[tx.itemQuality]) or { r = 0.5, g = 0.5, b = 0.5 }
            button.iconBorder:SetBackdropBorderColor(q.r, q.g, q.b, 1)
            button.iconBorder:Show()
            button.itemLink = tx.itemLink
            button.exactMoney = nil
            if not tx.itemName then color = C.notice end -- Name wird noch vom Server geladen
            what = string.format("%s%dx %s", sign, tx.count or 0, tx.itemName or tx.itemLink or L["CORE_ITEM_INFO_PENDING"])
        end

        local hex = string.format("|cff%02x%02x%02x", color[1] * 255, color[2] * 255, color[3] * 255)
        local who = ""
        if showPlayer or (tx.player and button.selectedPlayer and tx.player ~= button.selectedPlayer) then
            local r, g, b = ClassColor(tx.player or "?")
            who = string.format("|cff%02x%02x%02x%s|r  ", r * 255, g * 255, b * 255, tx.player or "?")
        end
        button.line:SetText(who .. hex .. verb .. what .. "|r")
        button.sub:SetText(Ago(tx.ts) .. "  ·  " .. TxWhere(tx))
    end
end

local function MakeList(parent, rowHeight, initFn, frameType)
    local box = CreateFrame("Frame", nil, parent, "WowScrollBoxList")
    local bar = CreateFrame("EventFrame", nil, parent, "MinimalScrollBar")
    bar:SetPoint("TOPLEFT", box, "TOPRIGHT", 4, 0)
    bar:SetPoint("BOTTOMLEFT", box, "BOTTOMRIGHT", 4, 0)
    local view = CreateScrollBoxListLinearView()
    view:SetElementExtent(rowHeight)
    view:SetElementFactory(function(factory)
        factory(frameType or "Frame", initFn)
    end)
    ScrollUtil.InitScrollBoxListWithScrollBar(box, bar, view)
    return box, bar
end

-- ============================================================
-- Seite "Uebersicht"
-- ============================================================
local overviewPage = NewPage()
pages.overview = overviewPage

local ovCards = {
    goldIn  = MakeCard(overviewPage, L["UI_CARD_GOLD_IN"]),
    goldOut = MakeCard(overviewPage, L["UI_CARD_GOLD_OUT"]),
    net     = MakeCard(overviewPage, L["UI_CARD_NET"]),
    items   = MakeCard(overviewPage, L["UI_CARD_ITEMS"]),
}
local ovCardRow = CardRow(overviewPage, { ovCards.goldIn, ovCards.goldOut, ovCards.net, ovCards.items })
ovCardRow:SetPoint("TOPLEFT", overviewPage, "TOPLEFT", 0, 0)
ovCardRow:SetPoint("TOPRIGHT", overviewPage, "TOPRIGHT", 0, 0)

-- rechts: hoechste Bilanz
local ovTop = NewFrame(overviewPage)
Theme.Skin(ovTop, "panel")
ovTop:SetWidth(TOP_WIDTH)
ovTop:SetPoint("TOPRIGHT", ovCardRow, "BOTTOMRIGHT", 0, -GAP)
ovTop:SetPoint("BOTTOMRIGHT", overviewPage, "BOTTOMRIGHT", 0, 0)
if ovTop.SetClipsChildren then ovTop:SetClipsChildren(true) end -- bei kleinem Fenster Zeilen abschneiden

local ovTopTitle = Text(ovTop, "GameFontNormal")
ovTopTitle:SetPoint("TOPLEFT", 10, -9)
ovTopTitle:SetText(L["UI_TOP_TITLE"])

local SelectPlayer -- Vorwaertsdeklaration (Seite "Mitglieder")
local TOP_ROWS = 10
local ovTopRows = {}
for i = 1, TOP_ROWS do
    local r = CreateFrame("Button", nil, ovTop)
    r:SetHeight(22)
    r:SetPoint("TOPLEFT", ovTop, "TOPLEFT", 4, -30 - (i - 1) * 22)
    r:SetPoint("TOPRIGHT", ovTop, "TOPRIGHT", -4, -30 - (i - 1) * 22)
    r.hl = r:CreateTexture(nil, "BACKGROUND")
    r.hl:SetAllPoints()
    Theme.Tint(r.hl, "rowHover")
    r.hl:Hide()
    r.rank = Text(r, "GameFontDisableSmall", "textDim")
    r.rank:SetPoint("LEFT", 6, 0)
    r.rank:SetWidth(18)
    r.rank:SetJustifyH("RIGHT")
    r.net = Text(r, "GameFontHighlightSmall")
    r.net:SetPoint("RIGHT", -6, 0)
    r.name = Text(r, "GameFontHighlightSmall")
    r.name:SetPoint("LEFT", r.rank, "RIGHT", 8, 0)
    r.name:SetPoint("RIGHT", r.net, "LEFT", -6, 0)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r:SetScript("OnEnter", function(self)
        self.hl:Show()
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(L["UI_TOP_HINT"], 1, 1, 1)
        GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) self.hl:Hide(); GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self)
        if self.playerName and SelectPlayer then SelectPlayer(self.playerName) end
    end)
    r:Hide()
    ovTopRows[i] = r
end

-- links: letzte Vorgaenge
local ovFeed = NewFrame(overviewPage)
Theme.Skin(ovFeed, "panel")
ovFeed:SetPoint("TOPLEFT", ovCardRow, "BOTTOMLEFT", 0, -GAP)
ovFeed:SetPoint("BOTTOMRIGHT", ovTop, "BOTTOMLEFT", -GAP, 0)

local ovFeedTitle = Text(ovFeed, "GameFontNormal")
ovFeedTitle:SetPoint("TOPLEFT", 10, -9)
ovFeedTitle:SetText(L["UI_FEED_TITLE"])

local ovFeedCount = Text(ovFeed, "GameFontDisableSmall", "textDim")
ovFeedCount:SetPoint("TOPRIGHT", -10, -11)

local ovFeedBox = MakeList(ovFeed, TX_ROW_HEIGHT, MakeTxRowInit(true))
ovFeedBox:SetPoint("TOPLEFT", ovFeed, "TOPLEFT", 4, -30)
ovFeedBox:SetPoint("BOTTOMRIGHT", ovFeed, "BOTTOMRIGHT", -22, 4)

-- Leerzustand: erklaert, WARUM nichts da ist, statt leere Flaechen zu zeigen
local ovEmpty = NewFrame(overviewPage)
Theme.Skin(ovEmpty, "panel")
ovEmpty:SetPoint("TOPLEFT", ovCardRow, "BOTTOMLEFT", 0, -GAP)
ovEmpty:SetPoint("BOTTOMRIGHT", overviewPage, "BOTTOMRIGHT", 0, 0)
ovEmpty:Hide()

local ovEmptyTitle = Text(ovEmpty, "GameFontNormalLarge")
ovEmptyTitle:SetPoint("TOP", 0, -28)
ovEmptyTitle:SetText(L["UI_EMPTY_TITLE"])

local ovEmptyBody = Text(ovEmpty, "GameFontHighlight")
ovEmptyBody:SetPoint("TOP", ovEmptyTitle, "BOTTOM", 0, -14)
ovEmptyBody:SetWidth(460)
ovEmptyBody:SetJustifyH("CENTER")
ovEmptyBody:SetSpacing(4)

local ovEmptyNote = Text(ovEmpty, "GameFontDisableSmall", "textDim")
ovEmptyNote:SetPoint("TOP", ovEmptyBody, "BOTTOM", 0, -16)
ovEmptyNote:SetWidth(460)
ovEmptyNote:SetJustifyH("CENTER")
ovEmptyNote:SetText(L["UI_EMPTY_LIMIT"])

local function SetCard(card, text, color, tooltip)
    card.value:SetText(text)
    card.value:SetTextColor(unpack(color or C.textBright))
    card.tooltip = tooltip
end

-- Die vier Kacheln (Uebersicht und Spielerdetails) gleich befuellen.
-- Nullwerte grau statt gruen/rot, damit "nichts passiert" nicht wie
-- ein Ergebnis aussieht.
local function FillCards(cards, goldIn, goldOut, itemsIn, itemsOut)
    local net = goldIn - goldOut
    SetCard(cards.goldIn, goldIn > 0 and ("+" .. MoneyShort(goldIn)) or MoneyShort(0),
        goldIn > 0 and C.green or C.neutral, MoneyExact(goldIn))
    SetCard(cards.goldOut, goldOut > 0 and ("-" .. MoneyShort(goldOut)) or MoneyShort(0),
        goldOut > 0 and C.red or C.neutral, MoneyExact(goldOut))
    SetCard(cards.net, SignedMoney(net), NetColor(net),
        (net < 0 and "-" or "") .. MoneyExact(net) .. "\n\n" .. L["UI_CARD_NET_TOOLTIP"])
    local items
    if itemsIn == 0 and itemsOut == 0 then
        items = "0  /  0"
    else
        items = string.format("|cff2ecc71+%s|r  /  |cffe74c3c-%s|r", Thousands(itemsIn), Thousands(itemsOut))
    end
    SetCard(cards.items, items, (itemsIn == 0 and itemsOut == 0) and C.neutral or C.textBright, L["UI_CARD_ITEMS_TOOLTIP"])
end

local function RefreshOverview()
    local since = PeriodSince()
    local t = DB.GetGuildTotals(since)
    FillCards(ovCards, t.goldIn, t.goldOut, t.itemsIn, t.itemsOut)
    ovCardRow.Layout()

    if t.txCount == 0 then
        ovFeed:Hide()
        ovTop:Hide()
        ovEmpty:Show()
        if DB.CountTransactions() > 0 then
            ovEmptyTitle:SetText(L["UI_EMPTY_PERIOD"])
            ovEmptyBody:SetText(L["UI_EMPTY_PERIOD_HINT"])
        else
            ovEmptyTitle:SetText(L["UI_EMPTY_TITLE"])
            local scan = LastScanInfo()
            local body = L["UI_EMPTY_BODY"] .. "\n\n"
            if not scan then
                body = body .. L["UI_EMPTY_NEVER"]
            else
                local when = Ago(scan.at)
                if (scan.tabs or 0) == 0 then
                    body = body .. string.format(L["UI_EMPTY_NO_TABS"], when)
                else
                    body = body .. string.format(L["UI_EMPTY_NOTHING_YET"], when)
                end
            end
            ovEmptyBody:SetText(body)
        end
        return
    end

    ovEmpty:Hide()
    ovFeed:Show()
    ovTop:Show()
    ovFeedCount:SetText(string.format(L["UI_FEED_COUNT"], t.txCount, t.players))
    ovFeedBox:SetDataProvider(CreateDataProvider(DB.SearchTransactions({ sinceTs = since, limit = 200 })))

    local list = DB.GetPlayerList("net", since)
    for i = 1, TOP_ROWS do
        local r, e = ovTopRows[i], list[i]
        if e then
            r.playerName = e.name
            r.rank:SetText(i .. ".")
            r.name:SetText(e.name)
            r.name:SetTextColor(ClassColor(e.name))
            r.net:SetText(SignedMoney(e.net))
            r.net:SetTextColor(unpack(NetColor(e.net)))
            r:Show()
        else
            r.playerName = nil
            r:Hide()
        end
    end
end

-- ============================================================
-- Seite "Mitglieder"
-- ============================================================
local membersPage = NewPage()
pages.members = membersPage

local mLeft = NewFrame(membersPage)
Theme.Skin(mLeft, "panel")
mLeft:SetPoint("TOPLEFT", membersPage, "TOPLEFT", 0, 0)
mLeft:SetPoint("BOTTOMLEFT", membersPage, "BOTTOMLEFT", 0, 0)
mLeft:SetWidth(LEFT_WIDTH)

local RefreshList, RefreshDetail -- Vorwaertsdeklaration

local searchBox = CreateFrame("EditBox", nil, mLeft, "InputBoxTemplate")
searchBox:SetHeight(20)
searchBox:SetPoint("TOPLEFT", mLeft, "TOPLEFT", 16, -10)
searchBox:SetPoint("TOPRIGHT", mLeft, "TOPRIGHT", -10, -10)
searchBox:SetAutoFocus(false)
searchBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
searchBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
Theme.SkinInput(searchBox)

-- Platzhaltertext, solange das Feld leer ist
local searchPlaceholder = Text(searchBox, "GameFontDisableSmall", "textDim")
searchPlaceholder:SetPoint("LEFT", 2, 0)
searchPlaceholder:SetText(L["UI_FILTER_PLACEHOLDER"])
local function UpdatePlaceholder()
    searchPlaceholder:SetShown((searchBox:GetText() or "") == "" and not searchBox:HasFocus())
end
searchBox:SetScript("OnEditFocusGained", UpdatePlaceholder)
searchBox:SetScript("OnEditFocusLost", UpdatePlaceholder)
searchBox:SetScript("OnTextChanged", function()
    UpdatePlaceholder()
    RefreshList()
end)

local sortLabel = Text(mLeft, "GameFontHighlightSmall", "textDim")
sortLabel:SetPoint("TOPLEFT", mLeft, "TOPLEFT", 10, -42)
sortLabel:SetText(L["UI_SORT_LABEL"])

local sortMode = "net"
local sortSeg
sortSeg = MakeSegments(mLeft, {
    { key = "net",      label = L["UI_SORT_NET"] },
    { key = "activity", label = L["UI_SORT_ACTIVITY"] },
    { key = "name",     label = L["UI_SORT_NAME"] },
}, function(key)
    sortMode = key
    sortSeg:SetActive(key)
    RefreshList()
end)
sortSeg:SetPoint("LEFT", sortLabel, "RIGHT", 6, 0)
sortSeg:SetActive("net")

local selectedPlayer = nil
local memberScrollBox

local function InitMemberRow(button, e)
    if not button.initialized then
        button.initialized = true
        button.hl = button:CreateTexture(nil, "BACKGROUND")
        button.hl:SetAllPoints()
        button.hl:Hide()

        button.sel = button:CreateTexture(nil, "BACKGROUND")
        button.sel:SetAllPoints()
        button.sel:Hide()
        button.selBar = button:CreateTexture(nil, "ARTWORK")
        button.selBar:SetWidth(3)
        button.selBar:SetPoint("TOPLEFT")
        button.selBar:SetPoint("BOTTOMLEFT")
        button.selBar:Hide()

        button.net = Text(button, "GameFontHighlight")
        button.net:SetPoint("TOPRIGHT", -8, -6)
        button.name = Text(button, "GameFontNormal")
        button.name:SetPoint("TOPLEFT", 10, -6)
        button.name:SetPoint("RIGHT", button.net, "LEFT", -6, 0)
        button.name:SetJustifyH("LEFT")
        button.name:SetWordWrap(false)
        button.sub = Text(button, "GameFontDisableSmall", "textDim")
        button.sub:SetPoint("BOTTOMLEFT", 10, 6)
        button.sub:SetPoint("RIGHT", button, "RIGHT", -8, 0)
        button.sub:SetJustifyH("LEFT")
        button.sub:SetWordWrap(false)

        button:SetScript("OnEnter", function(self) self.hl:Show() end)
        button:SetScript("OnLeave", function(self) self.hl:Hide() end)
        button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        if _G.GrindkeepStyle then _G.GrindkeepStyle.ApplyToFrame(button) end
    end

    button.hl:SetColorTexture(unpack(Theme.Color("rowHover")))
    button.sel:SetColorTexture(unpack(Theme.Color("rowSelect")))
    button.selBar:SetColorTexture(unpack(Theme.Color("accent")))
    button.playerName = e.name
    button.name:SetText(e.name)
    button.name:SetTextColor(ClassColor(e.name))
    button.net:SetText(SignedMoney(e.net))
    button.net:SetTextColor(unpack(NetColor(e.net)))
    local s = e.summary or {}
    local last = (s.lastActivity or 0) > 0 and Ago(s.lastActivity) or "-"
    button.sub:SetText(string.format(L["UI_MEMBER_SUB"], s.txCount or 0, last))

    local isSel = selectedPlayer == e.name
    button.sel:SetShown(isSel)
    button.selBar:SetShown(isSel)

    button:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" then
            ShowPlayerContextMenu(e.name, self)
        else
            selectedPlayer = e.name
            memberScrollBox:ForEachFrame(function(b)
                local on = b.playerName == selectedPlayer
                b.sel:SetShown(on)
                b.selBar:SetShown(on)
            end)
            RefreshDetail()
        end
    end)
end

memberScrollBox = MakeList(mLeft, MEMBER_ROW_HEIGHT, InitMemberRow, "Button")
memberScrollBox:SetPoint("TOPLEFT", mLeft, "TOPLEFT", 4, -68)
memberScrollBox:SetPoint("BOTTOMRIGHT", mLeft, "BOTTOMRIGHT", -22, 4)

local membersEmpty = Text(mLeft, "GameFontDisableSmall", "textDim")
membersEmpty:SetPoint("TOPLEFT", mLeft, "TOPLEFT", 12, -80)
membersEmpty:SetPoint("RIGHT", mLeft, "RIGHT", -12, 0)
membersEmpty:SetJustifyH("LEFT")
membersEmpty:Hide()

-- rechts: Details zum gewaehlten Spieler
local mRight = NewFrame(membersPage)
Theme.Skin(mRight, "panel")
mRight:SetPoint("TOPLEFT", mLeft, "TOPRIGHT", GAP, 0)
mRight:SetPoint("BOTTOMRIGHT", membersPage, "BOTTOMRIGHT", 0, 0)

local mPlaceholder = Text(mRight, "GameFontHighlight", "textDim")
mPlaceholder:SetPoint("CENTER", 0, 20)
mPlaceholder:SetWidth(320)
mPlaceholder:SetJustifyH("CENTER")
mPlaceholder:SetText(L["UI_SELECT_PLAYER"])

local detail = CreateFrame("Frame", nil, mRight)
detail:SetPoint("TOPLEFT", 10, -10)
detail:SetPoint("BOTTOMRIGHT", -10, 6)
detail:Hide()

local detailName = Text(detail, "GameFontNormalLarge")
detailName:SetPoint("TOPLEFT", 2, -2)

local detailSub = Text(detail, "GameFontDisableSmall", "textDim")
detailSub:SetPoint("TOPLEFT", detailName, "BOTTOMLEFT", 0, -4)
detailSub:SetPoint("RIGHT", detail, "RIGHT", 0, 0)
detailSub:SetJustifyH("LEFT")
detailSub:SetWordWrap(false)

local dCards = {
    goldIn  = MakeCard(detail, L["UI_CARD_GOLD_IN"], 50),
    goldOut = MakeCard(detail, L["UI_CARD_GOLD_OUT"], 50),
    net     = MakeCard(detail, L["UI_CARD_NET"], 50),
    items   = MakeCard(detail, L["UI_CARD_ITEMS"], 50),
}
local dCardRow = CardRow(detail, { dCards.goldIn, dCards.goldOut, dCards.net, dCards.items }, 50)
dCardRow:SetPoint("TOPLEFT", detail, "TOPLEFT", 0, -44)
dCardRow:SetPoint("TOPRIGHT", detail, "TOPRIGHT", 0, -44)

local currentFilter = "all"
local filterSeg
filterSeg = MakeSegments(detail, {
    { key = "all",  label = L["UI_TAB_ALL"] },
    { key = "gold", label = L["UI_TAB_GOLD"] },
    { key = "item", label = L["UI_TAB_ITEMS"] },
}, function(key)
    currentFilter = key
    filterSeg:SetActive(key)
    RefreshDetail()
end)
filterSeg:SetPoint("TOPLEFT", dCardRow, "BOTTOMLEFT", 0, -12)
filterSeg:SetActive("all")

local txInit = MakeTxRowInit(false)
local txScrollBox = MakeList(detail, TX_ROW_HEIGHT, function(button, tx)
    button.selectedPlayer = selectedPlayer
    txInit(button, tx)
end)
txScrollBox:SetPoint("TOPLEFT", filterSeg, "BOTTOMLEFT", 0, -8)
txScrollBox:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -18, 0)

local detailEmpty = Text(detail, "GameFontDisableSmall", "textDim")
detailEmpty:SetPoint("TOPLEFT", filterSeg, "BOTTOMLEFT", 2, -14)
detailEmpty:SetText(L["UI_DETAIL_EMPTY"])
detailEmpty:Hide()

local function FilteredList()
    local list = DB.GetPlayerList(sortMode, PeriodSince())
    local filter = (searchBox:GetText() or ""):lower()
    if filter == "" then return list end
    local out = {}
    for _, entry in ipairs(list) do
        if entry.name:lower():find(filter, 1, true) then table.insert(out, entry) end
    end
    return out
end

function RefreshList()
    local list = FilteredList()
    memberScrollBox:SetDataProvider(CreateDataProvider(list))
    if #list == 0 then
        membersEmpty:SetText((searchBox:GetText() or "") ~= "" and L["UI_MEMBERS_NO_MATCH"] or L["UI_MEMBERS_EMPTY"])
        membersEmpty:Show()
    else
        membersEmpty:Hide()
    end
end

function RefreshDetail()
    if not selectedPlayer then
        detail:Hide()
        mPlaceholder:Show()
        return
    end
    mPlaceholder:Hide()
    detail:Show()

    local since = PeriodSince()
    local details = DB.GetPlayerDetails(selectedPlayer, since)
    detailName:SetText(selectedPlayer)
    detailName:SetTextColor(ClassColor(selectedPlayer))

    local parts = {}
    if details and details.isTwinkOf then
        table.insert(parts, string.format(L["UI_TWINK_OF_SUFFIX"], details.isTwinkOf))
    end
    if details and details.twinks and #details.twinks > 0 then
        table.insert(parts, string.format(L["UI_TWINKS_LINE"], table.concat(details.twinks, ", ")))
    end
    table.insert(parts, L["UI_DETAIL_RIGHTCLICK"])
    detailSub:SetText(table.concat(parts, "  ·  "))

    local agg = details and details.aggregated or { goldDeposited = 0, goldWithdrawn = 0, itemDeposits = 0, itemWithdrawals = 0 }
    FillCards(dCards, agg.goldDeposited, agg.goldWithdrawn, agg.itemDeposits, agg.itemWithdrawals)
    dCardRow.Layout()

    -- Hauptcharakter und seine Twinks zusammen, im gewaehlten Zeitraum
    local txs = DB.SearchTransactions({
        player = selectedPlayer,
        kind = (currentFilter == "gold" or currentFilter == "item") and currentFilter or nil,
        sinceTs = since,
        limit = 1000,
    })
    txScrollBox:SetDataProvider(CreateDataProvider(txs))
    detailEmpty:SetShown(#txs == 0)
end

-- ============================================================
-- Reiter umschalten, eingebettete Seiten
-- ============================================================
-- Suche, Bestand und Loot werden erst eingebettet, wenn alle Dateien
-- geladen sind (UI.lua laedt vor Search.lua und Stock.lua).
local function EnsurePages()
    for _, t in ipairs(TABS) do
        if t.module and not pages[t.key] then
            local mod = _G[t.module]
            if mod and mod.Embed then
                local ok, frame = pcall(mod.Embed, content)
                if ok and frame then
                    pages[t.key] = frame
                    if _G.GrindkeepStyle then _G.GrindkeepStyle.ApplyToFrame(frame) end
                    pcall(Theme.SkinTree, frame)
                    -- Eigener Hintergrund, sonst scheint bei durchsichtigen
                    -- Designs die Spielwelt durch die Seite
                    if frame.SetBackdrop then Theme.Skin(frame, "panel") end
                end
            end
        end
    end
    if _G.GrindkeepSearchUI and _G.GrindkeepSearchUI.SetPeriod then
        _G.GrindkeepSearchUI.SetPeriod(periodDays)
    end
    LayoutTabs()
end

function RefreshActive()
    if not MainFrame:IsShown() then return end
    RefreshStatus()
    if activeTab == "overview" then
        RefreshOverview()
    elseif activeTab == "members" then
        RefreshList()
        RefreshDetail()
    elseif activeTab == "search" and _G.GrindkeepSearchUI then
        _G.GrindkeepSearchUI.Refresh()
    elseif activeTab == "stock" and _G.GrindkeepStockUI and _G.GrindkeepStockUI.Refresh then
        _G.GrindkeepStockUI.Refresh()
    elseif activeTab == "collect" and _G.GrindkeepCollectUI then
        _G.GrindkeepCollectUI.Refresh()
    elseif activeTab == "loot" and _G.GrindkeepLootUI then
        _G.GrindkeepLootUI.Refresh()
    end
end

SelectTab = function(key)
    if not TabAvailable(key) then key = "overview" end
    activeTab = key
    for k, b in pairs(tabButtons) do
        local on = k == key
        b.underline:SetShown(on)
        b.label:SetTextColor(unpack(Theme.Color(on and "text" or "textDim")))
    end
    for k, p in pairs(pages) do
        p:SetShown(k == key)
    end
    local usesPeriod = USES_PERIOD[key] and true or false
    periodLabel:SetShown(usesPeriod)
    periodSeg:SetShown(usesPeriod)
    RefreshActive()
end

SelectPlayer = function(name)
    selectedPlayer = name
    SelectTab("members")
end

local function ShowTab(key)
    EnsurePages()
    if isMinimized then minimizeBtn:Click() end
    MainFrame:Show()
    SelectTab(key)
end

local function ToggleTab(key)
    if MainFrame:IsShown() and activeTab == key then
        MainFrame:Hide()
    else
        ShowTab(key)
    end
end

-- ============================================================
-- Aussenschnittstelle
-- ============================================================
local function Toggle()
    if MainFrame:IsShown() then
        MainFrame:Hide()
    else
        EnsurePages()
        MainFrame:Show()
    end
end

_G.GrindkeepUI = {
    Frame = MainFrame,
    Toggle = Toggle,
    ShowTab = ShowTab,
    ToggleTab = ToggleTab,
    SelectPlayer = function(name)
        EnsurePages()
        MainFrame:Show()
        SelectPlayer(name)
    end,
    ActiveTab = function() return activeTab end,
    GetPeriodDays = function() return periodDays end,
    -- Nur neu zeichnen, wenn das Fenster offen ist; sonst holt OnShow
    -- beim naechsten Oeffnen frische Daten.
    Refresh = function()
        if MainFrame:IsShown() then RefreshActive() end
    end,
    ShowTwinkAssignPopup = ShowTwinkAssignPopup,
}

-- Aeltere Stellen lesen Farben aus C - bei jedem Designwechsel angleichen.
local function SyncPalette()
    C.selectBorder = Theme.Color("accent")
    C.accentFill = Theme.Color("accentFill")
    C.rowHover = Theme.Color("rowHover")
    C.rowSelect = Theme.Color("rowSelect")
    C.textBright = Theme.Color("text")
    C.textDim = Theme.Color("textDim")
    C.textMid = Theme.Color("textMid")
end
SyncPalette()
Theme.OnChange(function()
    SyncPalette()
    if MainFrame:IsShown() then SelectTab(activeTab) end
end)

MainFrame:SetScript("OnShow", function()
    RequestRoster()
    ReadRoster()
    local guildName = GetGuildInfo and GetGuildInfo("player")
    guildText:SetText(type(guildName) == "string" and guildName or "")
    SelectTab(activeTab)
end)

local rosterFrame = CreateFrame("Frame")
rosterFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
rosterFrame:SetScript("OnEvent", function()
    ReadRoster()
    if MainFrame:IsShown() and (activeTab == "members" or activeTab == "overview") then RefreshActive() end
end)

-- ============================================================
-- Minimap-Knopf
--
-- Bewusst selbst gebaut statt ueber eine Fremdbibliothek (LibDBIcon):
-- das Addon kommt bisher ohne jede Abhaengigkeit aus, und fuer einen
-- Knopf, der sich um einen Kreis schieben laesst, ist eine komplette
-- Bibliothek samt Einbettung nicht noetig. Die Position wird als Winkel
-- gespeichert, damit sie auch dann stimmt, wenn die Minimap eine andere
-- Groesse hat oder verschoben wurde.
-- ============================================================
local MINIMAP_RADIUS = 80

local minimapButton = CreateFrame("Button", "GrindkeepMinimapButton", Minimap)
minimapButton:SetSize(31, 31)
minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 8)
minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapButton:RegisterForDrag("LeftButton")

local mmOverlay = minimapButton:CreateTexture(nil, "OVERLAY")
mmOverlay:SetSize(53, 53)
mmOverlay:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
mmOverlay:SetPoint("TOPLEFT")

local mmIcon = minimapButton:CreateTexture(nil, "ARTWORK")
mmIcon:SetSize(19, 19)
mmIcon:SetPoint("TOPLEFT", 7, -6)
-- Muenzbeutel-Symbol: passt zu "Bank/Gold" und existiert seit jeher.
mmIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_02")
mmIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

local function UpdateMinimapButtonPosition(angleDeg)
    local rad = math.rad(angleDeg or 215)
    -- Radius an die tatsaechliche Minimap-Groesse anpassen (sie ist je nach
    -- Client unterschiedlich gross); MINIMAP_RADIUS nur als Rueckfall.
    local w = Minimap.GetWidth and Minimap:GetWidth() or 0
    local radius = (w and w > 0) and (w / 2 + 10) or MINIMAP_RADIUS
    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", math.cos(rad) * radius, math.sin(rad) * radius)
end

minimapButton:SetScript("OnDragStart", function(self)
    self.isMoving = true
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local cx, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        cx, cy = cx / scale, cy / scale
        local angle = math.deg(math.atan2(cy - my, cx - mx))
        UpdateMinimapButtonPosition(angle)
        if DB and DB.SetSetting then DB.SetSetting("minimapAngle", angle) end
    end)
end)

minimapButton:SetScript("OnDragStop", function(self)
    self.isMoving = false
    self:SetScript("OnUpdate", nil)
end)

minimapButton:SetScript("OnClick", function(_, button)
    if button == "RightButton" then
        if _G.GrindkeepStockUI then _G.GrindkeepStockUI.Toggle() end
    else
        Toggle()
    end
end)

minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(L["MINIMAP_TOOLTIP_TITLE"])
    GameTooltip:AddLine(L["MINIMAP_TOOLTIP_LEFT"], 1, 1, 1)
    GameTooltip:AddLine(L["MINIMAP_TOOLTIP_RIGHT"], 1, 1, 1)
    GameTooltip:AddLine(L["MINIMAP_TOOLTIP_DRAG"], 0.6, 0.6, 0.6)
    GameTooltip:Show()
end)
minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- Position und Sichtbarkeit setzt ApplySavedSettings() nach dem Laden der
-- gespeicherten Daten; bis dahin die Standardposition.
UpdateMinimapButtonPosition(215)

-- ============================================================
-- Eigener Reiter im Gildenbank-Fenster (neben "Info")
--
-- Das Gildenbank-Fenster ist ein nachladbares Blizzard-Addon
-- (Blizzard_GuildBankUI) - der Reiter kann also erst gebaut werden,
-- wenn dieses geladen ist. Der Knopf wird ans Fenster selbst gehaengt
-- und verschwindet damit automatisch mit ihm. Findet sich das Fenster
-- oder die vorhandenen Reiter nicht (anderer Client, andere Namen),
-- passiert einfach nichts - ohne Fehlermeldung.
-- ============================================================
local bankTabButton, bankTabTemplate
local bankTabHooked = false
-- Letztes Ergebnis der Reiter-Suche, fuer "/gkeep banktab"
local bankTabDiag = { frame = false, source = "-", count = 0, kind = "-", reason = "not tried" }

-- Gibt es eine Vorlage auf diesem Client? CreateFrame mit einer
-- unbekannten Vorlage wirft nicht zuverlaessig einen Fehler, sondern
-- erzeugt teils einen leeren Knopf - deshalb vorher nachsehen.
local function TemplateExists(name)
    if C_XMLUtil and C_XMLUtil.GetTemplateInfo then
        local ok, info = pcall(C_XMLUtil.GetTemplateInfo, name)
        return ok and info ~= nil
    end
    return true -- ohne Pruefmoeglichkeit einfach versuchen
end

local function IsButton(f)
    if type(f) ~= "table" or f == bankTabButton or not f.GetObjectType then return false end
    local ok, t = pcall(f.GetObjectType, f)
    return ok and (t == "Button" or t == "CheckButton")
end

-- Beschriftungen der Blizzard-Reiter unten im Gildenbank-Fenster. Werden
-- nur gebraucht, falls die Reiter weder feste Namen noch eine Liste haben.
local function KnownTabTexts()
    local t = {}
    for _, key in ipairs({ "GUILD_BANK", "GUILD_BANK_LOG", "GUILD_BANK_MONEY_LOG",
                           "GUILD_BANK_TAB_INFO", "GUILDBANK_INFO", "GUILD_BANK_INFO", "INFO", "LOG" }) do
        local v = _G[key]
        if type(v) == "string" and v ~= "" then t[v] = true end
    end
    for _, v in ipairs({ "Gildenbank", "Log", "Geldlog", "Info", "Guild Bank", "Money Log" }) do
        t[v] = true
    end
    return t
end

-- Die unteren Reiter (Gildenbank / Log / Geldlog / Info) finden. Je nach
-- Client heissen sie GuildBankFrameTab1..n, stehen in einer Liste am
-- Fenster (.Tabs / .BottomTabs) oder sind nur ueber ihre Beschriftung
-- zu erkennen - alles wird der Reihe nach versucht.
local function FindBankTabs(bankFrame)
    local tabs, seen = {}, {}
    local function add(f)
        if IsButton(f) and not seen[f] then seen[f] = true; tabs[#tabs + 1] = f end
    end

    local frameName = (bankFrame.GetName and bankFrame:GetName()) or "GuildBankFrame"
    for i = 1, 8 do add(_G[frameName .. "Tab" .. i]) end
    if #tabs > 0 then return tabs, "global" end

    for _, key in ipairs({ "Tabs", "BottomTabs", "TabButtons", "BottomTabButtons" }) do
        local list = bankFrame[key]
        if type(list) == "table" then
            for _, f in ipairs(list) do add(f) end
            if #tabs > 0 then return tabs, key end
        end
    end
    for i = 1, 8 do add(bankFrame["Tab" .. i]) end
    if #tabs > 0 then return tabs, "parentKey" end

    local texts = KnownTabTexts()
    if bankFrame.GetChildren then
        for _, child in ipairs({ bankFrame:GetChildren() }) do
            if IsButton(child) and child.GetText then
                local ok, txt = pcall(child.GetText, child)
                if ok and type(txt) == "string" and texts[txt] then add(child) end
            end
        end
    end
    if #tabs > 0 then return tabs, "text" end
    return tabs, nil
end

-- Den am weitesten rechts stehenden sichtbaren Reiter bestimmen und den
-- Abstand, den Blizzard zwischen den Reitern verwendet.
local function RightmostTab(tabs)
    local visible = {}
    for _, t in ipairs(tabs) do
        if not t.IsShown or t:IsShown() then visible[#visible + 1] = t end
    end
    if #visible == 0 then visible = tabs end
    local withPos = true
    for _, t in ipairs(visible) do
        if not (t.GetLeft and tonumber(t:GetLeft()) and tonumber(t:GetRight())) then withPos = false break end
    end
    if withPos then
        table.sort(visible, function(a, b) return a:GetLeft() < b:GetLeft() end)
    end
    local last = visible[#visible]
    local gap
    if withPos and #visible >= 2 then
        local prev = visible[#visible - 1]
        gap = last:GetLeft() - prev:GetRight()
        if gap < -30 or gap > 30 then gap = nil end -- unplausibel (andere Zeile)
    end
    return last, gap
end

-- Knopf an die richtige Stelle setzen. Wird bei jedem Oeffnen der Bank
-- erneut aufgerufen, weil Blizzard die Reiterbreiten erst dann anpasst.
local function PositionBankTab()
    local bankFrame = _G.GuildBankFrame
    if not (bankTabButton and bankFrame) then return end
    local tabs, source = FindBankTabs(bankFrame)
    bankTabDiag.source, bankTabDiag.count = source or "-", #tabs

    bankTabButton:ClearAllPoints()
    if #tabs > 0 then
        local last, gap = RightmostTab(tabs)
        if not gap then
            gap = (bankTabTemplate == "CharacterFrameTabButtonTemplate") and -15 or 3
        end
        if bankTabTemplate then
            bankTabButton:SetPoint("TOPLEFT", last, "TOPRIGHT", gap, 0)
        else
            bankTabButton:SetPoint("LEFT", last, "RIGHT", 4, 0)
        end
        bankTabDiag.reason = "ok"
    else
        -- Keine Reiter gefunden: trotzdem sichtbar unten rechts am Fenster
        -- statt stillschweigend gar nicht.
        bankTabButton:SetPoint("TOPRIGHT", bankFrame, "BOTTOMRIGHT", -8, 2)
        bankTabDiag.reason = "no tabs found - fallback position"
    end
end

local function CreateBankTabButton()
    local bankFrame = _G.GuildBankFrame
    bankTabDiag.frame = bankFrame and true or false
    if not bankFrame then
        bankTabDiag.reason = "GuildBankFrame missing"
        return
    end

    local wanted = DB.GetSetting("showBankTabButton") ~= false
    if bankTabButton then
        bankTabButton:SetShown(wanted)
        if wanted then PositionBankTab() end
        return
    end
    if not wanted then
        bankTabDiag.reason = "disabled in options"
        return
    end

    -- Reiter-Vorlage zuerst versuchen; klappt das, sieht der Knopf aus
    -- wie "Log"/"Geldlog"/"Info" daneben. Sonst ein normaler Knopf.
    local btn
    for _, template in ipairs({ "PanelTabButtonTemplate", "CharacterFrameTabTemplate", "CharacterFrameTabButtonTemplate" }) do
        if not btn and TemplateExists(template) then
            local ok, b = pcall(CreateFrame, "Button", nil, bankFrame, template)
            if ok and b then
                if b.GetFontString and b:GetFontString() then
                    btn, bankTabTemplate = b, template
                else
                    b:Hide() -- unbrauchbarer Rohling, nicht sichtbar lassen
                end
            end
        end
    end
    if not btn then
        local ok, b = pcall(CreateFrame, "Button", nil, bankFrame, "UIPanelButtonTemplate")
        if not ok or not b then
            bankTabDiag.reason = "CreateFrame failed"
            return
        end
        btn = b
        btn:SetSize(96, 22)
    end
    _G.GrindkeepBankTab = btn
    bankTabDiag.kind = bankTabTemplate or "UIPanelButtonTemplate"

    btn:SetText(L["BANK_TAB_LABEL"])
    btn:SetID(99) -- nicht in Blizzards Reiterverwaltung einreihen

    if bankTabTemplate then
        -- Breite am Text ausrichten, wie es Blizzards eigene Reiter tun
        if _G.PanelTemplates_TabResize then
            pcall(_G.PanelTemplates_TabResize, btn, 0)
        end
        if (tonumber(btn:GetWidth()) or 0) < 40 then btn:SetWidth(100) end
        if (tonumber(btn:GetHeight()) or 0) < 10 then btn:SetHeight(32) end
        if _G.PanelTemplates_DeselectTab then
            pcall(_G.PanelTemplates_DeselectTab, btn)
        end
    end

    if btn.SetFrameLevel and bankFrame.GetFrameLevel then
        btn:SetFrameLevel((bankFrame:GetFrameLevel() or 1) + 5)
    end

    btn:SetScript("OnClick", function()
        if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
            pcall(PlaySound, SOUNDKIT.IG_CHARACTER_INFO_TAB)
        end
        Toggle()
    end)

    bankTabButton = btn
    btn:Show()
    PositionBankTab()

    -- Bei jedem Oeffnen neu ausrichten (Reiterbreiten stehen erst dann fest)
    if not bankTabHooked and bankFrame.HookScript then
        bankTabHooked = true
        bankFrame:HookScript("OnShow", function()
            PositionBankTab()
            if C_Timer and C_Timer.After then C_Timer.After(0, PositionBankTab) end
        end)
    end
end

-- Der Reiter wird angelegt, sobald das Gildenbank-Fenster existiert: wenn
-- Blizzards Gildenbank-Modul nachgeladen wird, beim Oeffnen der Bank, und
-- beim Einloggen, falls ein anderes Addon das Modul schon frueher geladen hat.
-- Beim Oeffnen zusaetzlich kurz verzoegert, weil das Fenster erst nach dem
-- Ereignis erscheint.
local function TryCreateBankTab()
    CreateBankTabButton()
    if C_Timer and C_Timer.After then
        C_Timer.After(0.2, CreateBankTabButton)
    end
end

local bankTabWatcher = CreateFrame("Frame")
bankTabWatcher:RegisterEvent("ADDON_LOADED")
bankTabWatcher:RegisterEvent("PLAYER_LOGIN")
pcall(bankTabWatcher.RegisterEvent, bankTabWatcher, "GUILDBANKFRAME_OPENED")
pcall(bankTabWatcher.RegisterEvent, bankTabWatcher, "PLAYER_INTERACTION_MANAGER_FRAME_SHOW")
bankTabWatcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= "Blizzard_GuildBankUI" and arg1 ~= "Grindkeep" then return end
    end
    TryCreateBankTab()
end)

-- "/gkeep banktab": zeigt, was beim Anlegen des Reiters gefunden wurde
local function BankTabDiagnose()
    CreateBankTabButton()
    local b = bankTabButton
    local p = function(s) print("|cffd4a017Grindkeep|r banktab: " .. s) end
    p("version=" .. tostring((C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata("Grindkeep", "Version"))
        or (GetAddOnMetadata and GetAddOnMetadata("Grindkeep", "Version")) or "?")
        .. " setting=" .. tostring(DB.GetSetting("showBankTabButton") ~= false))
    p("GuildBankFrame=" .. tostring(bankTabDiag.frame) .. " tabs=" .. tostring(bankTabDiag.count)
        .. " via=" .. tostring(bankTabDiag.source))
    p("button=" .. tostring(b ~= nil) .. " type=" .. tostring(bankTabDiag.kind)
        .. (b and (" shown=" .. tostring(b:IsShown()) .. " visible=" .. tostring(b:IsVisible())
            .. " size=" .. math.floor(tonumber(b:GetWidth()) or 0) .. "x" .. math.floor(tonumber(b:GetHeight()) or 0)) or ""))
    p("status=" .. tostring(bankTabDiag.reason))
end

_G.GrindkeepUI.MinimapButton = minimapButton
_G.GrindkeepUI.SetMinimapButtonShown = function(shown)
    if shown then minimapButton:Show() else minimapButton:Hide() end
end
_G.GrindkeepUI.SetBankTabShown = function()
    CreateBankTabButton()
end
_G.GrindkeepUI.BankTabDiagnose = BankTabDiagnose
_G.GrindkeepUI.LayoutHeaderButtons = LayoutHeaderButtons
_G.GrindkeepUI.ShowSearch = function(text)
    if _G.GrindkeepSearchUI then _G.GrindkeepSearchUI.Show(text) end
end
_G.GrindkeepUI.EnsurePages = EnsurePages

-- Wird von Core.lua aufgerufen, sobald die gespeicherten Daten geladen
-- sind (ADDON_LOADED). Vorher wuerden hier nur die Standardwerte stehen.
_G.GrindkeepUI.ApplySavedSettings = function()
    RestoreWindowSize()
    UpdateMinimapButtonPosition(DB.GetSetting("minimapAngle") or 215)
    minimapButton:SetShown(DB.GetSetting("showMinimapButton") ~= false)
    EnsurePages()
    Theme.ApplyAll() -- gespeichertes Design erst jetzt bekannt
end

-- Schrift/Groesse/Deckkraft zentral ueber Style.lua (siehe dort)
if _G.GrindkeepStyle then
    _G.GrindkeepStyle.RegisterAndApply(MainFrame)
end

-- Eintrag im Addon-Menue neben der Minimap (neuere Clients, siehe
-- AddonCompartmentFunc in der .toc): Linksklick oeffnet das Hauptfenster,
-- Rechtsklick den Bestand.
function Grindkeep_OnAddonCompartmentClick(_, button)
    if button == "RightButton" then
        if _G.GrindkeepStockUI then _G.GrindkeepStockUI.Toggle() end
    else
        Toggle()
    end
end

--[[
    Grindkeep - Help.lua

    Kurze Erklaerung im Spiel: was macht dieses Addon, wo finde ich was,
    und was muss ich einmalig einrichten.

    Hintergrund: Die Rueckmeldung beim ersten Einsatz auf einem fremden
    Realm war "ich verstehe die Funktionen nicht, anscheinend fehlt auch
    noch vieles" - und das lag nicht nur am kaputten Ladevorgang. Ein
    Addon, dessen Zweck man erst aus einer Chat-Befehlsliste erschliessen
    muss, hat ein Erklaerungsproblem. Deshalb dieses Fenster, erreichbar
    ueber das Fragezeichen oben im Hauptfenster oder /gkeep help.

    Bewusst als reiner Text mit Absaetzen statt als Assistent mit
    Schritten: das Addon muss nicht eingerichtet werden, um zu
    funktionieren - es laeuft sofort mit. Nur die Mindestbestaende sind
    eine bewusste Entscheidung des Nutzers.
]]

local DB = _G.GrindkeepDatabase
local L = _G.GrindkeepLocale

local C = {
    bg      = { 18 / 255, 18 / 255, 22 / 255, 0.95 },
    panelBg = { 24 / 255, 24 / 255, 29 / 255, 0.95 },
    border  = { 0x2a / 255, 0x2d / 255, 0x34 / 255, 1 },
    accent  = { 0xc9 / 255, 0xa2 / 255, 0x27 / 255, 1 },
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

local EDGE = 13

local HelpFrame = CreateFrame("Frame", "GrindkeepHelpFrame", UIParent, "BackdropTemplate")
HelpFrame:SetSize(520, 460)
HelpFrame:SetPoint("CENTER")
HelpFrame:SetFrameStrata("DIALOG")
HelpFrame:SetMovable(true)
HelpFrame:EnableMouse(true)
HelpFrame:RegisterForDrag("LeftButton")
HelpFrame:SetScript("OnDragStart", HelpFrame.StartMoving)
HelpFrame:SetScript("OnDragStop", HelpFrame.StopMovingOrSizing)
if _G.GrindkeepTheme then _G.GrindkeepTheme.Skin(HelpFrame, "window") else ApplyWindowBackdrop(HelpFrame) end
HelpFrame:Hide()
tinsert(UISpecialFrames, "GrindkeepHelpFrame")

local header = CreateFrame("Frame", nil, HelpFrame, "BackdropTemplate")
header:SetHeight(36)
header:SetPoint("TOPLEFT", EDGE, -EDGE)
header:SetPoint("TOPRIGHT", -EDGE, -EDGE)
if _G.GrindkeepTheme then _G.GrindkeepTheme.Skin(header, "panel") else Backdrop(header, C.panelBg, C.border) end
header:EnableMouse(true)
header:RegisterForDrag("LeftButton")
header:SetScript("OnDragStart", function() HelpFrame:StartMoving() end)
header:SetScript("OnDragStop", function() HelpFrame:StopMovingOrSizing() end)

local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
title:SetPoint("LEFT", 10, 0)
title:SetText(L["HELP_TITLE"])

local closeBtn = CreateFrame("Button", nil, header, "UIPanelCloseButton")
if _G.GrindkeepTheme then _G.GrindkeepTheme.SkinClose(closeBtn) end
closeBtn:SetPoint("RIGHT", -4, 0)
closeBtn:SetScript("OnClick", function() HelpFrame:Hide() end)

-- Scrollbarer Textbereich: der Text ist laenger als das Fenster hoch
-- ist, und ein abgeschnittener Hilfetext waere besonders aergerlich.
local scrollFrame = CreateFrame("ScrollFrame", "GrindkeepHelpScroll", HelpFrame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 4, -10)
scrollFrame:SetPoint("BOTTOMRIGHT", HelpFrame, "BOTTOMRIGHT", -EDGE - 24, EDGE + 4)

local content = CreateFrame("Frame", nil, scrollFrame)
content:SetSize(440, 10)
scrollFrame:SetScrollChild(content)

local lastAnchor = nil
local totalHeight = 8

-- Hoehe einer Textzeile ermitteln. GetStringHeight liefert 0, solange
-- das Layout noch nicht berechnet ist (und auf ungewoehnlichen Clients
-- theoretisch gar nichts) - deshalb mit Rueckfallwert, sonst waere die
-- Gesamthoehe des Scrollbereichs falsch und der Text unten abgeschnitten.
local function MeasuredHeight(fs, fallback)
    local h = fs.GetStringHeight and fs:GetStringHeight()
    if type(h) ~= "number" or h <= 0 then return fallback end
    return h
end

local function AddHeading(text)
    local fs = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fs:SetTextColor(unpack(C.accent))
    fs:SetWidth(430)
    fs:SetJustifyH("LEFT")
    fs:SetText(text)
    if lastAnchor then
        fs:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -14)
    else
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
    end
    lastAnchor = fs
    totalHeight = totalHeight + MeasuredHeight(fs, 16) + 18
    return fs
end

local function AddText(text)
    local fs = content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetWidth(430)
    fs:SetJustifyH("LEFT")
    fs:SetSpacing(2)
    fs:SetText(text)
    if lastAnchor then
        fs:SetPoint("TOPLEFT", lastAnchor, "BOTTOMLEFT", 0, -5)
    else
        fs:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -4)
    end
    lastAnchor = fs
    totalHeight = totalHeight + MeasuredHeight(fs, 48) + 9
    return fs
end

AddHeading(L["HELP_H_WHAT"])
AddText(L["HELP_T_WHAT"])

AddHeading(L["HELP_H_WINDOWS"])
AddText(L["HELP_T_WINDOWS"])

AddHeading(L["HELP_H_STOCK"])
AddText(L["HELP_T_STOCK"])

AddHeading(L["HELP_H_STORAGE"])
AddText(L["HELP_T_STORAGE"])

AddHeading(L["HELP_H_LOOT"])
AddText(L["HELP_T_LOOT"])

AddHeading(L["HELP_H_ALTS"])
AddText(L["HELP_T_ALTS"])

AddHeading(L["HELP_H_LIMITS"])
AddText(L["HELP_T_LIMITS"])

AddHeading(L["HELP_H_COMMANDS"])
AddText(L["HELP_T_COMMANDS"])

content:SetHeight(totalHeight + 20)

-- Beim Oeffnen neu vermessen: nach einer groesseren Schrift (Style.lua)
-- sind die Absaetze hoeher als beim Laden, sonst waere das Ende abgeschnitten.
HelpFrame:SetScript("OnShow", function()
    local h = 8
    for _, child in ipairs({ content:GetRegions() }) do
        if child.GetObjectType and child:GetObjectType() == "FontString" then
            h = h + MeasuredHeight(child, 16) + 12
        end
    end
    content:SetHeight(math.max(h, totalHeight) + 20)
end)

local function Toggle()
    if HelpFrame:IsShown() then HelpFrame:Hide() else HelpFrame:Show() end
end

_G.GrindkeepHelpUI = {
    Frame = HelpFrame,
    Toggle = Toggle,
    Show = function() HelpFrame:Show() end,
}

if _G.GrindkeepStyle then
    _G.GrindkeepStyle.RegisterAndApply(HelpFrame)
end

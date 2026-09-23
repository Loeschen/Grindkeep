--[[
    Grindkeep - Style.lua

    Schriftart, Schriftgroesse und Fenster-Transparenz fuer alle
    Grindkeep-Fenster.

    Ansatz: Statt in jedem Fenster jede einzelne Textzeile von Hand
    anzufassen, laeuft Apply() einmal durch den kompletten Frame-Baum
    eines angemeldeten Fensters und setzt die Schrift auf jeder
    gefundenen FontString. Beim ersten Durchlauf merkt sich jede
    FontString ihre urspruengliche Groesse; die eingestellte Groesse
    wirkt danach als FAKTOR darauf. Das ist wichtig, damit die
    Abstufung erhalten bleibt - Fenstertitel bleibt groesser als
    Unterzeile, auch bei 130%.

    Warum kein fester Punktwert fuer alles? Weil dann jede Zeile gleich
    gross waere und die Fenster ihre Struktur verlieren wuerden.

    Schriftdateien: WoW bringt nur eine Handvoll mit, und auf
    Clients anderer Sprachen heissen sie teilweise anders. Deshalb wird
    jede Schrift vor dem Uebernehmen geprueft (SetFont meldet selbst,
    ob die Datei geladen werden konnte) und bei Misserfolg auf die
    Standardschrift zurueckgefallen - statt dass Text unsichtbar wird.
]]

local DB = _G.GrindkeepDatabase
local L = _G.GrindkeepLocale

local Style = {}
_G.GrindkeepStyle = Style

-- Auswahl bewusst klein gehalten: nur Schriften, die WoW selbst
-- mitbringt. Eigene Schriftdateien mitzuliefern waere unnoetiger
-- Ballast und lizenzrechtlich heikel.
Style.Fonts = {
    { key = "default",  path = nil,                    label = "STYLE_FONT_DEFAULT" },
    { key = "arial",    path = "Fonts\\ARIALN.TTF",    label = "STYLE_FONT_ARIAL" },
    { key = "friz",     path = "Fonts\\FRIZQT__.TTF",  label = "STYLE_FONT_FRIZ" },
    { key = "morpheus", path = "Fonts\\MORPHEUS.TTF",  label = "STYLE_FONT_MORPHEUS" },
    { key = "skurri",   path = "Fonts\\SKURRI.TTF",    label = "STYLE_FONT_SKURRI" },
}

local function FontByKey(key)
    for _, f in ipairs(Style.Fonts) do
        if f.key == key then return f end
    end
    return Style.Fonts[1]
end

local registered = {}

function Style.Register(frame)
    if not frame then return end
    for _, f in ipairs(registered) do
        if f == frame then return end
    end
    table.insert(registered, frame)
end

-- Fenster, das in ein anderes eingebettet wurde, wieder abmelden: sonst
-- wuerde die Transparenz doppelt wirken (eigene * die des Hauptfensters).
function Style.Unregister(frame)
    for i = #registered, 1, -1 do
        if registered[i] == frame then table.remove(registered, i) end
    end
    if frame and frame.SetAlpha then pcall(frame.SetAlpha, frame, 1) end
end

local function ApplyToFontString(region, fontPath, scale)
    -- Ursprungszustand einmalig merken - ab dann ist er die Basis fuer
    -- jede weitere Aenderung (sonst wuerde sich die Skalierung bei
    -- jedem Aufruf erneut auf die bereits skalierte Groesse anwenden).
    if not region.gkBaseSize then
        local basePath, baseSize, baseFlags = region:GetFont()
        if not baseSize then return end
        region.gkBasePath = basePath
        region.gkBaseSize = baseSize
        region.gkBaseFlags = baseFlags
    end

    local size = math.max(6, math.floor(region.gkBaseSize * (scale or 1) + 0.5))
    local path = fontPath or region.gkBasePath
    if not path then return end

    -- SetFont meldet false, wenn die Schriftdatei nicht geladen werden
    -- konnte. Dann zurueck auf die urspruengliche Schrift, sonst bliebe
    -- der Text unsichtbar.
    local ok = region:SetFont(path, size, region.gkBaseFlags)
    if ok == false and region.gkBasePath then
        region:SetFont(region.gkBasePath, size, region.gkBaseFlags)
    end
end

local function Walk(frame, fontPath, scale, depth)
    if not frame or depth > 12 then return end

    if frame.GetRegions then
        local regions = { frame:GetRegions() }
        for _, region in ipairs(regions) do
            if region and region.GetObjectType and region:GetObjectType() == "FontString" then
                ApplyToFontString(region, fontPath, scale)
            end
        end
    end

    if frame.GetChildren then
        local children = { frame:GetChildren() }
        for _, child in ipairs(children) do
            Walk(child, fontPath, scale, depth + 1)
        end
    end
end

function Style.Apply()
    local fontKey = DB.GetSetting("fontChoice") or "default"
    local scale = tonumber(DB.GetSetting("fontScale")) or 1
    local opacity = tonumber(DB.GetSetting("windowOpacity")) or 1

    local font = FontByKey(fontKey)

    for _, frame in ipairs(registered) do
        local ok = pcall(Walk, frame, font.path, scale, 1)
        if not ok then
            -- Ein einzelnes Fenster mit ungewoehnlichem Aufbau darf
            -- nicht den Rest blockieren.
        end
        if frame.SetAlpha then
            pcall(frame.SetAlpha, frame, math.max(0.3, math.min(1, opacity)))
        end
    end
end

-- Nach dem Anmelden eines Fensters einmal anwenden, damit auch spaet
-- geladene Fenster (z.B. Stock.lua) sofort richtig aussehen.
-- Fuer Zeilen, die eine Liste erst spaeter (beim Scrollen) anlegt: die
-- aktuelle Einstellung auf genau diesen Frame anwenden, ohne ihn dauerhaft
-- anzumelden.
function Style.ApplyToFrame(frame)
    if not frame then return end
    local font = FontByKey(DB.GetSetting("fontChoice") or "default")
    local scale = tonumber(DB.GetSetting("fontScale")) or 1
    pcall(Walk, frame, font.path, scale, 1)
end

-- Ein bisher eigenstaendiges Fenster (Suche, Bestand, Loot) als Seite in
-- das Hauptfenster einbetten: neuer Elternrahmen, fuellt dessen Flaeche,
-- kein eigener Rahmen/Hintergrund, nicht mehr verschieb- oder
-- vergroesserbar, und Escape schliesst das Hauptfenster statt der Seite.
function Style.EmbedFrame(frame, parent)
    frame:SetParent(parent)
    frame:ClearAllPoints()
    frame:SetAllPoints(parent)
    if frame.SetBackdrop then pcall(frame.SetBackdrop, frame, nil) end
    if frame.SetMovable then frame:SetMovable(false) end
    if frame.SetResizable then frame:SetResizable(false) end
    for _, script in ipairs({ "OnDragStart", "OnDragStop", "OnMouseDown", "OnMouseUp" }) do
        frame:SetScript(script, nil)
    end
    if frame.EnableMouse then frame:EnableMouse(false) end
    if parent.GetFrameStrata and frame.SetFrameStrata then
        frame:SetFrameStrata(parent:GetFrameStrata() or "HIGH")
    end
    if parent.GetFrameLevel and frame.SetFrameLevel then
        frame:SetFrameLevel((tonumber(parent:GetFrameLevel()) or 1) + 1)
    end
    local name = frame.GetName and frame:GetName()
    if name and type(UISpecialFrames) == "table" then
        for i = #UISpecialFrames, 1, -1 do
            if UISpecialFrames[i] == name then table.remove(UISpecialFrames, i) end
        end
    end
    Style.Unregister(frame)
    frame:Hide()
    return frame
end

function Style.RegisterAndApply(frame)
    Style.Register(frame)
    Style.Apply()
end

-- ============================================================
-- Slash-Befehle (werden von Core.lua aufgerufen)
-- ============================================================
function Style.HandleCommand(args)
    local sub = args and args[1] and args[1]:lower()

    if sub == "font" and args[2] then
        local key = args[2]:lower()
        local found = nil
        for _, f in ipairs(Style.Fonts) do
            if f.key == key then found = f end
        end
        if not found then
            local names = {}
            for _, f in ipairs(Style.Fonts) do table.insert(names, f.key) end
            print("|cff2ecc71[Grindkeep]|r " .. string.format(L["STYLE_FONT_UNKNOWN"], table.concat(names, ", ")))
            return
        end
        DB.SetSetting("fontChoice", found.key)
        Style.Apply()
        print("|cff2ecc71[Grindkeep]|r " .. string.format(L["STYLE_FONT_SET"], found.key))
        return
    end

    if sub == "size" and tonumber(args[2]) then
        local percent = tonumber(args[2])
        percent = math.max(70, math.min(160, percent))
        DB.SetSetting("fontScale", percent / 100)
        Style.Apply()
        print("|cff2ecc71[Grindkeep]|r " .. string.format(L["STYLE_SIZE_SET"], percent))
        return
    end

    if sub == "opacity" and tonumber(args[2]) then
        local percent = math.max(30, math.min(100, tonumber(args[2])))
        DB.SetSetting("windowOpacity", percent / 100)
        Style.Apply()
        print("|cff2ecc71[Grindkeep]|r " .. string.format(L["STYLE_OPACITY_SET"], percent))
        return
    end

    print("|cff2ecc71[Grindkeep]|r " .. L["STYLE_USAGE"])
end

--[[
    Statische Pruefungen ohne Spielumgebung (Lua 5.1):

    1. Uebersetzungen: jeder Schluessel hat enUS und deDE, Platzhalter
       stehen in beiden Sprachen in derselben Reihenfolge, kein "|" im
       Text (WoW-Steuerzeichen), jeder im Code benutzte Schluessel existiert.
    2. Deutsche Texte mit echten Umlauten statt ae/oe/ue-Umschreibungen.
    3. API-Aufrufe, die es nicht auf jedem Zielclient gibt, stehen nur mit
       Existenzpruefung im Code.

    Aufruf aus dem Hauptordner: lua5.1 tests/static.lua
]]

local failures, warnings = 0, 0
local function fail(msg)
    failures = failures + 1
    io.stdout:write("FAIL [static] " .. msg .. "\n")
end

-- Bekannte Altlasten aus 1.4.1, ueber die noch entschieden wird (Roland).
-- Sie werden angezeigt, lassen den Lauf aber nicht scheitern. Mit
-- STRICT=1 zaehlen sie wie Fehler. Sobald sie behoben sind: hier streichen.
local STRICT = os.getenv("STRICT") == "1"
-- ("|" in Texten und "vorgaenge" sind seit 1.4.2 behoben und zaehlen wieder als Fehler.)
local KNOWN_OPEN = {
    ["api:Core.lua:QueryGuildBankLog"] = true, -- Existenz nur indirekt geprueft
}
local function known(category, msg)
    if KNOWN_OPEN[category] and not STRICT then
        warnings = warnings + 1
        io.stdout:write("WARN [static] (bekannt offen) " .. msg .. "\n")
    else
        fail(msg)
    end
end

local function readFile(path)
    local f = assert(io.open(path, "rb"))
    local s = f:read("*a")
    f:close()
    return s
end

-- Addon-Dateien laut .toc
local files = {}
for line in readFile("Grindkeep.toc"):gmatch("[^\r\n]+") do
    if not line:match("^%s*#") and line:match("%.lua%s*$") then
        files[#files + 1] = line:match("^%s*(.-)%s*$")
    end
end

-- ------------------------------------------------------------
-- 1. Uebersetzungen
-- ------------------------------------------------------------
_G.GetLocale = function() return "deDE" end
local src = readFile("Locale.lua")
src = src:gsub("_G%.GrindkeepLocale = L", "_G.GrindkeepLocale = L; _G.GK_STRINGS = STRINGS")
assert(loadstring(src, "Locale.lua"))()
local STRINGS = _G.GK_STRINGS

local function specs(s)
    local t = {}
    for sp in s:gmatch("%%[%-%d%.]*[sdfx%%]") do
        if sp ~= "%%" then t[#t + 1] = sp:sub(-1) end
    end
    return table.concat(t)
end

local keys = {}
for k in pairs(STRINGS) do keys[#keys + 1] = k end
table.sort(keys)

for _, k in ipairs(keys) do
    local e = STRINGS[k]
    for _, lang in ipairs({ "enUS", "deDE" }) do
        if type(e[lang]) ~= "string" or e[lang] == "" then fail(k .. ": " .. lang .. " fehlt") end
        if type(e[lang]) == "string" and e[lang]:find("|", 1, true) then
            known("pipe", k .. ": " .. lang .. " enthaelt | (WoW-Steuerzeichen)")
        end
    end
    if e.enUS and e.deDE and specs(e.enUS) ~= specs(e.deDE) then
        fail(k .. ": Platzhalter unterschiedlich (" .. specs(e.enUS) .. " / " .. specs(e.deDE) .. ")")
    end
end

-- Im Code benutzte Schluessel
for _, file in ipairs(files) do
    local code = readFile(file)
    for k in code:gmatch('L%["([%w_]+)"%]') do
        if not STRINGS[k] then fail(file .. ": Schluessel " .. k .. " fehlt in Locale.lua") end
    end
end

-- ------------------------------------------------------------
-- 2. Echte Umlaute in deutschen Texten
-- ------------------------------------------------------------
-- Typische Umschreibungen; Befehlswoerter nach "/gkeep" sind ausgenommen.
local TRANSLIT = {
    "fuer", "ueber", "Ueber", "aender", "Aender", "koenn", "moecht", "muess", "waehl", "Waehl", "traeg",
    "Traeg", "Faech", "faech", "staend", "oeffn", "Oeffn", "groess", "Groess", "schluess", "Schluess",
    "zurueck", "fueg", "Vorgaeng", "vorgaeng", "naechst", "spaet", "Menue", "Knoepf", "knoepf", "saetz",
    "tatsaech", "Qualitaet", "qualitaet", "loesch", "Loesch", "hoeh", "Hoeh", "gruen", "Gruen", "Uebersicht",
    "uebernehm", "Gebuehr", "Stueck", "stueck", "wuerd", "haett", "waer", "Bestaend", "gefuellt", "fuell",
    "zaehl", "Zaehl", "laeuft", "laedt", "haelt", "enthaelt", "faellt", "erhaelt", "Eintraeg", "eintraeg",
    "Gegenstaend", "Ausruest", "Aufbewahrungsdau", "koennt", "duerf", "Duerf", "fuehr", "Fuehr", "wuensch",
    "Wuensch", "Pruef", "pruef", "Uebertr", "uebertr", "Rueck", "rueck",
}
for _, k in ipairs(keys) do
    local de = STRINGS[k].deDE or ""
    local text = de:gsub("/gkeep[^%s]*%s+%S+", ""):gsub("/grindkeep[^%s]*%s+%S+", "")
    for _, frag in ipairs(TRANSLIT) do
        if text:find(frag, 1, true) and not (frag == "Aufbewahrungsdau") then
            known("translit:" .. frag, k .. ": deDE enthaelt Umschreibung '" .. frag .. "' statt Umlaut")
        end
    end
end

-- ------------------------------------------------------------
-- 3. API-Aufrufe nur mit Existenzpruefung
-- ------------------------------------------------------------
-- Globale Funktionen, die mindestens einem Zielclient fehlen (Forever hat
-- die alten Item-/Container-/Addon-Funktionen nicht mehr, Retail hat
-- einige Chat-/Gruppenfunktionen in C_-Namensraeume verschoben) oder die
-- nicht garantiert sind.
local RISKY = {
    "GetItemInfo", "GetItemIcon", "GetAddOnMetadata", "GetContainerItemInfo", "GetContainerNumSlots",
    "SendChatMessage", "InviteUnit", "InviteByName", "ChatFrame_SendTell", "ChatFrame_OpenChat",
    "GuildRoster", "GetLootMethod", "ChatEdit_InsertLink", "issecretvalue", "GetAutoCompleteRealms",
    "GetServerTime", "GetNormalizedRealmName", "GetRealmName", "QueryGuildBankTabInfo", "QueryGuildBankTab",
    "QueryGuildBankLog", "GetGuildBankItemInfo", "GetGuildBankItemLink", "GetGuildBankTabInfo",
    "GetNumGuildBankTabs", "GetCoinTextureString", "BreakUpLargeNumbers", "GetFileIDFromPath",
    "GetInstanceInfo", "IsInRaid", "IsInGroup", "GetNumGuildMembers", "GetItemInfoInstant", "GetBuildInfo",
    "GetItemQualityByID",
}

local function StripComment(line)
    -- grob: Kommentar ab "--" ausserhalb von Strings abschneiden
    local inStr, i = nil, 1
    while i <= #line do
        local c = line:sub(i, i)
        if inStr then
            if c == "\\" then i = i + 1 elseif c == inStr then inStr = nil end
        elseif c == '"' or c == "'" then
            inStr = c
        elseif line:sub(i, i + 1) == "--" then
            return line:sub(1, i - 1), line:sub(i)
        end
        i = i + 1
    end
    return line, ""
end

local function StripStrings(code)
    return (code:gsub('"[^"]*"', '""'):gsub("'[^']*'", "''"))
end

local function Guarded(name, text)
    local n = name
    return text:find("if%s+" .. n .. "[%s%)]") or text:find("if%s+not%s+" .. n .. "[%s%)]")
        or text:find("and%s+" .. n .. "[%s%)%.]") or text:find("or%s+" .. n .. "[%s%)]")
        or text:find(n .. "%s+then") or text:find(n .. "%s+and") or text:find("pcall%(%s*" .. n .. "[%s,%)]")
        or text:find("not%s+" .. n .. "[%s%)]") or text:find("%(%s*" .. n .. "%s+and")
        or text:find("type%(%s*" .. n .. "%s*%)") or text:find("[{,]%s*" .. n .. "%s*}")
        or text:find("=%s*" .. n .. "%s*$") or text:find("or%s+" .. n .. "%s*$")
end

for _, file in ipairs(files) do
    local lines = {}
    for line in (readFile(file) .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    local inBlockComment = false
    for i, raw in ipairs(lines) do
        local line = raw
        if inBlockComment then
            if line:find("%]%]") then inBlockComment = false end
            line = ""
        elseif line:find("^%s*%-%-%[%[") then
            inBlockComment = not line:find("%]%]")
            line = ""
        end
        local code, comment = StripComment(line)
        code = StripStrings(code)
        for _, name in ipairs(RISKY) do
            -- Aufruf oder Verwendung als globale Variable (nicht als Feld x.Name / x:Name)
            local s = 1
            while true do
                local a, b = code:find(name, s, true)
                if not a then break end
                local before = a > 1 and code:sub(a - 1, a - 1) or ""
                local after = code:sub(b + 1, b + 1)
                if not before:match("[%w_%.:]") and not after:match("[%w_]") then
                    -- Pruefung in dieser oder den zwei Zeilen davor, oder ausdruecklich vermerkt
                    local ctx = StripStrings((lines[i - 2] or "") .. " " .. (lines[i - 1] or "") .. " " .. code)
                    if not Guarded(name, ctx) and not comment:find("Existenz geprueft") then
                        known("api:" .. file .. ":" .. name, ("%s:%d: %s ohne Existenzpruefung"):format(file, i, name))
                    end
                end
                s = b + 1
            end
        end
    end
end

io.stdout:write(("[static] %d Schluessel geprueft, %s, %d bekannte offene Punkte\n"):format(#keys,
    failures == 0 and "keine Fehler" or (failures .. " Fehler"), warnings))
os.exit(failures == 0 and 0 or 1)

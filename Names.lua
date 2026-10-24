--[[
    Grindkeep - Names.lua

    Charakternamen einheitlich zerlegen und vergleichen.

    Hintergrund (im echten WoW-Forever-Client gemessen):
      - GetGuildRosterInfo liefert den Namen OHNE Realm, aber mit
        Nachnamen: "Bobcation Immolation".
      - Chat- und Addon-Absender koennen "Name-Realm" sein:
        "Bobcation Immolation-Realm".
      - Retail liefert im Roster "Name-Realm".

    Regeln:
      - Leerzeichen gehoeren zum Namen und werden nie entfernt.
      - Ein Anhang "-Xyz" gilt NUR dann als Realm, wenn Xyz der eigene oder
        ein verbundener Realm ist. Alles andere (z.B. ein Nachname mit
        Bindestrich oder ein fremder Realm) bleibt Teil des Namens. Damit
        kann sich niemand von einem fremden Realm als Offizier ausgeben,
        indem er dessen Namen traegt.
      - Fehlt auf einer Seite der Realm (Forever-Roster, eigener Name), wird
        nur der Name verglichen.
      - Zwei volle Namen ("Vorname Nachname") muessen genau gleich sein:
        "Anna Meier-Schulz" und "Anna Krause" sind zwei Charaktere.
      - Nennt eine Seite nur den Vornamen ("Anna-Realm"; laut 1.4.0 liefern
        Forever-Addon-Absender teils nur den Vornamen), gilt das als
        UNSICHERER Treffer (Same liefert dann exact = false). Wer daraus
        Rechte ableitet (Comm.lua), nimmt bei mehreren Treffern den
        niedrigsten Rang.
]]

local Names = {}
_G.GrindkeepNames = Names

-- Realm wie GetNormalizedRealmName: ohne Leerzeichen und Bindestriche
local function NormalizeRealm(realm)
    if type(realm) ~= "string" then return nil end
    realm = realm:gsub("[%s%-]", "")
    if realm == "" then return nil end
    return realm
end
Names.NormalizeRealm = NormalizeRealm

-- Eigener Realm (normalisiert) oder nil, solange der Client ihn nicht kennt
function Names.OwnRealm()
    if GetNormalizedRealmName then
        local ok, r = pcall(GetNormalizedRealmName)
        r = ok and NormalizeRealm(r) or nil
        if r then return r end
    end
    if GetRealmName then
        local ok, r = pcall(GetRealmName)
        if ok then return NormalizeRealm(r) end
    end
    return nil
end

-- Eigener und verbundene Realms als Menge. Bewusst nicht dauerhaft
-- zwischengespeichert: vor dem Einloggen kennt der Client den Realm noch
-- nicht, und die Abfrage ist billig.
function Names.KnownRealms()
    local set = {}
    local own = Names.OwnRealm()
    if own then set[own:lower()] = own end
    if GetAutoCompleteRealms then
        local ok, list = pcall(GetAutoCompleteRealms)
        if ok and type(list) == "table" then
            for _, r in ipairs(list) do
                local n = NormalizeRealm(r)
                if n then set[n:lower()] = n end
            end
        end
    end
    return set
end

-- Aussen kuerzen, innen mehrfache Leerzeichen zu einem - nie ganz entfernen
local function Trim(s)
    return (s:gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- Zerlegt einen Namen. Rueckgabe: base, realm (realm nur, wenn der Anhang
-- ein bekannter Realm ist, sonst nil und base = ganzer Name).
function Names.Split(name, realms)
    if type(name) ~= "string" then return nil, nil end
    name = Trim(name)
    if name == "" then return nil, nil end
    realms = realms or Names.KnownRealms()
    -- Von rechts nach links jeden Bindestrich pruefen: Realms wie
    -- "Azjol-Nerub" kommen normalisiert ohne Bindestrich, sicher ist sicher.
    local pos = #name
    while pos > 1 do
        local dash = nil
        for i = pos, 2, -1 do
            if name:sub(i, i) == "-" then dash = i break end
        end
        if not dash then break end
        local suffix = NormalizeRealm(name:sub(dash + 1))
        local realm = suffix and realms[suffix:lower()]
        if realm then
            local base = Trim(name:sub(1, dash - 1))
            if base ~= "" then return base, realm end
        end
        pos = dash - 1
    end
    return name, nil
end

-- Name ohne (bekannten) Realm - fuer Anzeige und Gruppierung
function Names.Base(name)
    local base = Names.Split(name)
    return base or (type(name) == "string" and name or "?")
end

-- Derselbe Charakter? Mit Realm auf beiden Seiten wird der Realm
-- mitverglichen, fehlt er auf einer Seite, zaehlt nur der Name.
-- Liefert zusaetzlich true als zweiten Wert, wenn der Vergleich exakt war
-- (beide Realms bekannt oder beide ohne Realm).
local function FirstWord(s) return s:match("^(%S+)") or s end

function Names.Same(a, b)
    local realms = Names.KnownRealms()
    local ba, ra = Names.Split(a, realms)
    local bb, rb = Names.Split(b, realms)
    if not ba or not bb then return false, false end
    local exactName = ba == bb
    if not exactName then
        -- Nur Vorname auf einer Seite, voller Name auf der anderen: unsicher
        local oneShort = (not ba:find(" ", 1, true)) ~= (not bb:find(" ", 1, true))
        if not (oneShort and FirstWord(ba) == FirstWord(bb)) then return false, false end
    end
    if ra and rb then
        local same = ra:lower() == rb:lower()
        return same, same and exactName
    end
    return true, exactName and (ra == nil and rb == nil)
end

-- Schluessel fuer gespeicherte Daten (Bilanzen, Twinks, Beute): voller Name
-- mit Nachnamen; Realm nur, wenn es ein verbundener, nicht der eigene ist.
-- Ein unbekannter Anhang bleibt Teil des Namens.
function Names.Key(name)
    if type(name) ~= "string" then return name end
    local base, realm = Names.Split(name)
    if not base then return "" end
    if base == "?" then return base end
    local own = Names.OwnRealm()
    if realm and (not own or realm:lower() ~= own:lower()) then return base .. "-" .. realm end
    return base
end

-- Eigener Charakter mit eigenem Realm ("Bobcation Immolation-Realm")
function Names.Me()
    local name = UnitName and UnitName("player")
    if type(name) ~= "string" or name == "" then return nil end
    local own = Names.OwnRealm()
    return own and (name .. "-" .. own) or name
end

--[[
    Grindkeep - Storage.lua

    Lager-Twinks: Taschen und Bank eigener Charaktere automatisch erfassen.

    Ein Charakter wird einmal als Lager markiert (Bestand-Seite oder
    "/gkeep lager an"). Ab dann liest Grindkeep bei ihm selbststaendig:
      - die Taschen: beim Einloggen und nach jeder Aenderung,
      - die Bank: nur solange sie geoeffnet ist (vorher kennt der Client
        ihren Inhalt nicht), beim Oeffnen und nach jeder Aenderung dort.
    Das Ergebnis landet in Database (account-weit), sodass jeder Charakter
    des Accounts den Stand aller Lager-Twinks sieht.

    Gebundene Gegenstaende (Ruhestein, eigene Ausruestung ...) werden
    uebersprungen - sie koennen ohnehin nicht weitergegeben werden und
    wuerden die Liste nur fuellen.

    Welche Taschen es gibt, unterscheidet sich je Client (Retail hat seit
    11.2 Bankfaecher statt Banktaschen, Forever/Classic die alten
    Banktaschen). Deshalb werden die Taschen-Nummern aus Blizzards eigener
    Liste (Enum.BagIndex) gelesen und nur bei deren Fehlen auf die alten
    festen Nummern zurueckgegriffen.
]]

local DB = _G.GrindkeepDatabase
local L = _G.GrindkeepLocale

local Storage = {}
_G.GrindkeepStorage = Storage

local SCAN_DELAY = 1.0

-- ------------------------------------------------------------
-- Welche Taschen gehoeren zu "Taschen" und welche zur "Bank"?
-- ------------------------------------------------------------
local function BagIds()
    local bags, bank = {}, {}
    local enum = Enum and Enum.BagIndex
    if type(enum) == "table" and next(enum) then
        for key, id in pairs(enum) do
            if type(id) == "number" and type(key) == "string" then
                if key == "Backpack" or key:match("^Bag_%d+$") or key == "ReagentBag" then
                    bags[id] = true
                elseif key == "Bank" or key:match("^BankBag_%d+$") or key == "Reagentbank"
                    or key:match("^CharacterBankTab_%d+$") then
                    bank[id] = true
                end
                -- AccountBankTab_* (Kriegsmeute-Bank) bewusst nicht: gehoert
                -- keinem Charakter und wuerde bei jedem Lager-Twink doppelt zaehlen.
            end
        end
    else
        local numBags = NUM_BAG_SLOTS or 4
        for i = 0, numBags do bags[i] = true end
        if NUM_TOTAL_EQUIPPED_BAG_SLOTS and NUM_TOTAL_EQUIPPED_BAG_SLOTS > numBags then
            bags[NUM_TOTAL_EQUIPPED_BAG_SLOTS] = true -- Reagenzientasche
        end
        bank[BANK_CONTAINER or -1] = true
        for i = numBags + 1, numBags + (NUM_BANKBAGSLOTS or 7) do bank[i] = true end
        if REAGENTBANK_CONTAINER then bank[REAGENTBANK_CONTAINER] = true end
    end
    -- Sicherheitshalber: eine Nummer nie doppelt (Taschen UND Bank)
    for id in pairs(bags) do bank[id] = nil end
    return bags, bank
end

local function NumSlots(bag)
    local f = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    if not f then return 0 end
    local ok, n = pcall(f, bag)
    return (ok and tonumber(n)) or 0
end

-- Einheitlich: count, itemID, link, quality - egal welche API der Client hat
local function SlotInfo(bag, slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local ok, info = pcall(C_Container.GetContainerItemInfo, bag, slot)
        if ok and type(info) == "table" then
            return info.stackCount, info.itemID, info.hyperlink, info.quality, info.isBound
        end
        return nil
    end
    if GetContainerItemInfo then
        local ok, _, count, _, quality, _, _, link, _, _, itemID = pcall(GetContainerItemInfo, bag, slot)
        if ok then return count, itemID, link, quality end
    end
    return nil
end

local function IsBound(bag, slot, flag)
    if flag ~= nil then return flag and true or false end
    if C_Item and C_Item.IsBound and ItemLocation and ItemLocation.CreateFromBagAndSlot then
        local ok, bound = pcall(function()
            return C_Item.IsBound(ItemLocation:CreateFromBagAndSlot(bag, slot))
        end)
        if ok then return bound and true or false end
    end
    return false
end

local function NameFromLink(link)
    if type(link) ~= "string" then return nil end
    local name = link:match("|h%[(.-)%]|h")
    if not name then return nil end
    -- Symbole der Qualitaetsstufen (Retail) u.ae. aus dem Namen entfernen
    name = name:gsub("|A.-|a", ""):gsub("|T.-|t", ""):gsub("|", "/"):gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" then return nil end -- Gegenstand noch nicht geladen
    return name
end

-- Liest eine Menge Taschen und fasst gleiche Gegenstaende zusammen.
function Storage.ReadBags(bagSet)
    local items = {}
    for bag in pairs(bagSet) do
        for slot = 1, NumSlots(bag) do
            local count, itemID, link, quality, boundFlag = SlotInfo(bag, slot)
            itemID = tonumber(itemID) or (type(link) == "string" and tonumber(link:match("|Hitem:(%d+)")))
            if itemID and (count or 0) > 0 and not IsBound(bag, slot, boundFlag) then
                local e = items[itemID]
                if not e then
                    e = { count = 0, itemLink = link, itemName = NameFromLink(link), itemQuality = quality }
                    items[itemID] = e
                end
                e.count = e.count + count
            end
        end
    end
    return items
end

-- ------------------------------------------------------------
-- Erfassen
-- ------------------------------------------------------------
local bankOpen = false
local pending = {}

local function CurrentKey() return DB.CharKey and DB.CharKey() end

local function Notify()
    if _G.GrindkeepUI and _G.GrindkeepUI.Refresh then _G.GrindkeepUI.Refresh() end
end

function Storage.ScanNow(part)
    local key = CurrentKey()
    if not key or not DB.IsStorageChar(key) then return false end
    local bags, bank = BagIds()
    if part == "bank" then
        if not bankOpen then return false end
        DB.SetStorageSnapshot(key, "bank", Storage.ReadBags(bank))
    else
        DB.SetStorageSnapshot(key, "bags", Storage.ReadBags(bags))
    end
    Notify()
    return true
end

-- Viele Taschen-Ereignisse kommen in Schueben: nur einmal kurz danach lesen.
local function Schedule(part)
    if pending[part] then return end
    pending[part] = true
    local function run()
        pending[part] = false
        Storage.ScanNow(part)
    end
    if C_Timer and C_Timer.After then C_Timer.After(SCAN_DELAY, run) else run() end
end

local BANKER = Enum and Enum.PlayerInteractionType and Enum.PlayerInteractionType.Banker or 8

local watcher = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "BANKFRAME_OPENED", "BANKFRAME_CLOSED",
    "PLAYERBANKSLOTS_CHANGED", "PLAYERREAGENTBANKSLOTS_CHANGED",
    "PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" }) do
    pcall(watcher.RegisterEvent, watcher, ev)
end
watcher:SetScript("OnEvent", function(_, event, arg1)
    if event == "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" then
        if arg1 ~= BANKER then return end
        event = "BANKFRAME_OPENED"
    elseif event == "PLAYER_INTERACTION_MANAGER_FRAME_HIDE" then
        if arg1 ~= BANKER then return end
        event = "BANKFRAME_CLOSED"
    end

    -- Solange die Bank offen ist, Taschen UND Bank sofort gemeinsam lesen:
    -- verschiebt jemand etwas und schliesst gleich danach die Bank, stimmen
    -- beide Staende trotzdem zusammen (sonst waere ein Gegenstand doppelt
    -- oder gar nicht gezaehlt).
    if event == "BANKFRAME_OPENED" then
        bankOpen = true
        Storage.ScanNow("bank")
        Storage.ScanNow("bags")
        Schedule("bank") -- falls der Inhalt beim Oeffnen noch nachlaedt
    elseif event == "BANKFRAME_CLOSED" then
        if bankOpen then
            Storage.ScanNow("bank")
            Storage.ScanNow("bags")
        end
        bankOpen = false
    elseif event == "PLAYERBANKSLOTS_CHANGED" or event == "PLAYERREAGENTBANKSLOTS_CHANGED" then
        if bankOpen then
            Storage.ScanNow("bank")
            Storage.ScanNow("bags")
        end
    elseif event == "BAG_UPDATE_DELAYED" then
        if bankOpen then
            Storage.ScanNow("bank")
            Storage.ScanNow("bags")
        else
            Schedule("bags")
        end
    elseif event == "PLAYER_LOGIN" then
        Schedule("bags")
    end
end)

-- ------------------------------------------------------------
-- Ein-/Ausschalten fuer den eingeloggten Charakter
-- ------------------------------------------------------------
function Storage.IsCurrentStorage()
    return DB.IsStorageChar(CurrentKey())
end

function Storage.SetCurrent(enabled)
    local key = CurrentKey()
    if not key then return false end
    DB.SetStorageChar(key, enabled)
    if enabled then
        Storage.ScanNow("bags")
        if bankOpen then Storage.ScanNow("bank") end
    end
    Notify()
    return true
end

function Storage.IsBankOpen() return bankOpen end

-- "/gkeep lager [an|aus|liste|entfernen <Name>]"
function Storage.HandleCommand(rest)
    local sub, arg = (rest or ""):match("^%s*(%S*)%s*(.-)%s*$")
    sub = (sub or ""):lower()
    local P = function(msg) print("|cff2ecc71[Grindkeep]|r " .. msg) end
    if sub == "an" or sub == "on" then
        Storage.SetCurrent(true)
        P(string.format(L["STORAGE_ON"], CurrentKey() or "?"))
    elseif sub == "aus" or sub == "off" then
        Storage.SetCurrent(false)
        P(string.format(L["STORAGE_OFF"], CurrentKey() or "?"))
    elseif sub == "entfernen" or sub == "remove" then
        local target
        for _, c in ipairs(DB.GetStorageChars(true)) do
            if c.key:lower() == arg:lower() or c.name:lower() == arg:lower() then target = c.key end
        end
        if target and DB.RemoveStorageChar(target) then
            P(string.format(L["STORAGE_REMOVED"], target))
            Notify()
        else
            P(string.format(L["STORAGE_NOT_FOUND"], arg))
        end
    else
        local list = DB.GetStorageChars()
        if #list == 0 then
            P(L["STORAGE_NONE"])
        else
            P(L["STORAGE_LIST_HEADER"])
            for _, c in ipairs(list) do
                local when = c.bankAt and date(L["DATE_FORMAT_SHORT"], c.bankAt) or L["STORAGE_BANK_NEVER"]
                P(string.format(L["STORAGE_LIST_LINE"], c.name, c.itemKinds, when))
            end
        end
        P(L["STORAGE_HELP"])
    end
end

-- Nur fuer Tests
Storage._BagIds = BagIds
Storage._SetBankOpen = function(v) bankOpen = v end

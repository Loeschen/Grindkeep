--[[
    Nachgebaute WoW-API fuer die Tests (Lua 5.1, ausserhalb des Spiels).

    Bildet nur ab, was Grindkeep beim Laden und in den getesteten Ablaeufen
    braucht. Zwei Profile:
      forever - WoW Forever (Interface 16001): ohne die alten globalen
                Funktionen, die dort entfernt sind (GetItemInfo, ...),
                Roster-Namen OHNE Realm, mit Nachnamen.
      retail  - Retail (120100/120105): Roster-Namen "Name-Realm",
                verbundene Realms, geheime Werte (issecretvalue).

    Nicht Teil des Addon-Pakets (.pkgmeta schliesst tests/ aus).
]]

local Stub = {}
Stub.printed = {}
Stub.timers = {}
Stub.frames = {}
Stub.sentAddon = {}
Stub.sentChat = {}

-- ------------------------------------------------------------
-- Widgets: bekannte Methoden echt, alles Methodenartige als No-op
-- ------------------------------------------------------------
local Methods = {}
local METHOD_PREFIXES = { "Set", "Get", "Is", "Has", "Enable", "Disable", "Register", "Unregister", "Show",
    "Hide", "Clear", "Start", "Stop", "Hook", "Highlight", "Add", "Scroll", "Init", "Lock", "Unlock", "Raise",
    "Lower", "Play", "Insert", "Release", "Flush", "Update", "Apply", "Adjust", "Refresh", "Reset", "Toggle",
    "Click", "Enumerate", "For", "Find", "Remove", "Select", "Deselect", "Cancel", "Load", "Mark", "Fade",
    "Can", "Do", "Run", "Invalidate", "Rebuild", "Layout", "Size", "Anchor", "Attach", "Detach" }

local function IsMethodName(k)
    if type(k) ~= "string" then return false end
    for _, p in ipairs(METHOD_PREFIXES) do
        if k:sub(1, #p) == p and (#k == #p or k:sub(#p + 1, #p + 1):match("[%u%d]")) then return true end
    end
    return false
end

local WidgetMT = {}
local NewWidget

WidgetMT.__index = function(t, k)
    local m = Methods[k]
    if m then return m end
    if type(k) == "string" and k:sub(1, 6) == "Create" then
        return function(self, ...) return NewWidget(k:sub(7), nil, self) end
    end
    if IsMethodName(k) then return function() return nil end end
    return nil
end

NewWidget = function(kind, name, parent)
    local w = setmetatable({ _kind = kind or "Frame", _name = name, _parent = parent, _scripts = {},
        _events = {}, _shown = true, _text = "" }, WidgetMT)
    table.insert(Stub.frames, w)
    if name then _G[name] = w end
    return w
end
Stub.NewWidget = NewWidget

function Methods:SetScript(what, fn) self._scripts[what] = fn end
function Methods:GetScript(what) return self._scripts[what] end
function Methods:HookScript(what, fn)
    local old = self._scripts[what]
    self._scripts[what] = function(...) if old then old(...) end fn(...) end
end
function Methods:RegisterEvent(ev)
    if Stub.unknownEvents and Stub.unknownEvents[ev] then error("unknown event " .. ev) end
    self._events[ev] = true
end
function Methods:UnregisterEvent(ev) self._events[ev] = nil end
function Methods:IsEventRegistered(ev) return self._events[ev] == true end
function Methods:Show()
    local was = self._shown
    self._shown = true
    if not was and self._scripts.OnShow then self._scripts.OnShow(self) end
end
function Methods:Hide()
    local was = self._shown
    self._shown = false
    if was and self._scripts.OnHide then self._scripts.OnHide(self) end
end
function Methods:SetShown(v) if v then self:Show() else self:Hide() end end
function Methods:IsShown() return self._shown end
function Methods:IsVisible() return self._shown end
function Methods:SetText(t) self._text = t == nil and "" or tostring(t) end
function Methods:GetText() return self._text end
function Methods:GetName() return self._name end
function Methods:GetParent() return self._parent end
function Methods:SetParent(p) self._parent = p end
function Methods:GetObjectType() return self._kind end
function Methods:GetFont() return "Fonts\\FRIZQT__.TTF", 12, "" end
function Methods:SetFont() return true end
function Methods:GetStringWidth() return 50 end
function Methods:GetStringHeight() return 14 end
function Methods:GetWidth() return 100 end
function Methods:GetHeight() return 20 end
function Methods:GetSize() return 100, 20 end
function Methods:GetFrameLevel() return 1 end
function Methods:GetCenter() return 0, 0 end
function Methods:GetEffectiveScale() return 1 end
function Methods:GetScale() return 1 end
function Methods:GetAlpha() return 1 end
function Methods:GetChecked() return self._checked or false end
function Methods:SetChecked(v) self._checked = v and true or false end
function Methods:GetNumPoints() return 0 end
function Methods:GetRegions() return end
function Methods:GetChildren() return end
function Methods:GetFontString() return nil end
function Methods:HasFocus() return self._focus or false end
function Methods:SetFocus() self._focus = true end
function Methods:ClearFocus() self._focus = false end
function Methods:GetNumber() return tonumber(self._text) or 0 end
function Methods:GetID() return self._id or 0 end
function Methods:SetID(id) self._id = id end
function Methods:GetFontObject() return nil end

-- ------------------------------------------------------------
-- Globale Umgebung
-- ------------------------------------------------------------
function Stub.Install(profile)
    Stub.profile = profile
    local forever = profile == "forever"

    _G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
        table.insert(Stub.printed, table.concat(parts, " "))
    end

    _G.CreateFrame = function(kind, name, parent, template) return NewWidget(kind, name, parent) end
    _G.UIParent = NewWidget("Frame", "UIParent")
    _G.Minimap = NewWidget("Frame", "Minimap")
    _G.GameTooltip = NewWidget("GameTooltip", "GameTooltip")
    _G.DEFAULT_CHAT_FRAME = NewWidget("Frame", "ChatFrame1")
    _G.ChatFontNormal = {}
    _G.UISpecialFrames = {}
    _G.time = function(t) if t then return os.time(t) end return Stub.now end
    _G.date = os.date
    _G.tinsert = table.insert
    _G.tremove = table.remove
    _G.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
    _G.hooksecurefunc = function() end
    _G.StaticPopupDialogs = {}
    _G.StaticPopup_Show = function() end
    _G.SlashCmdList = {}
    _G.OKAY, _G.CANCEL, _G.CLOSE, _G.YES, _G.NO = "Okay", "Cancel", "Close", "Yes", "No"
    _G.LOOT_ITEM = "%s receives loot: %s."
    _G.LOOT_ITEM_MULTIPLE = "%s receives loot: %sx%d."
    _G.LOOT_ITEM_SELF = "You receive loot: %s."
    _G.LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
    _G.RAID_CLASS_COLORS = { WARRIOR = { r = 0.78, g = 0.61, b = 0.43 } }
    _G.ITEM_QUALITY_COLORS = {}
    _G.SOUNDKIT = {}
    _G.PlaySound = function() end
    _G.IsShiftKeyDown = function() return false end
    _G.GetCursorPosition = function() return 0, 0 end
    _G.GetTime = function() return os.clock() end
    _G.GetServerTime = function() return Stub.now end
    _G.BreakUpLargeNumbers = function(n) return tostring(n) end
    _G.GetCoinTextureString = function(c) return tostring(c) .. "c" end
    _G.Mixin = function(o, ...) for i = 1, select("#", ...) do for k, v in pairs((select(i, ...))) do o[k] = v end end return o end
    _G.BackdropTemplateMixin = {}
    _G.CreateDataProvider = function(list) return { list = list } end
    _G.CreateScrollBoxListLinearView = function() return NewWidget("View") end
    _G.ScrollUtil = { InitScrollBoxListWithScrollBar = function() end }
    _G.ScrollBoxConstants = { RetainScrollPosition = true }
    _G.Enum = {
        PlayerInteractionType = { Banker = 8, GuildBanker = 10 },
        BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, ReagentBag = 5, Bank = -1 },
    }
    _G.C_Timer = { After = function(sec, fn) table.insert(Stub.timers, fn) end }

    -- Sprache und Uhr
    Stub.locale = Stub.locale or "deDE"
    _G.GetLocale = function() return Stub.locale end
    Stub.now = 1790000000

    -- Spieler, Realm, Gilde
    Stub.playerName = forever and "Bobcation Immolation" or "Bobcation"
    Stub.realm = "Testrealm"
    Stub.connected = nil
    if not forever then Stub.connected = { "Testrealm", "Nachbarrealm" } end
    _G.UnitName = function(unit) if unit == "player" then return Stub.playerName end end
    _G.UnitClass = function() return "Warrior", "WARRIOR" end
    _G.GetNormalizedRealmName = function() return Stub.realm end
    _G.GetRealmName = function() return Stub.realm end
    if Stub.connected then
        _G.GetAutoCompleteRealms = function() return Stub.connected end
    end
    _G.IsInGuild = function() return true end
    _G.GetGuildInfo = function() return "Die Grindgilde", "Offizier", 1, nil end
    Stub.roster = {}
    _G.GetNumGuildMembers = function() return #Stub.roster end
    _G.GetGuildRosterInfo = function(i)
        local r = Stub.roster[i]
        if not r then return nil end
        return r.name, r.rankName or "Rang", r.rank, 80, "Krieger", "Zone", "", "", true, 1, "WARRIOR"
    end
    _G.C_GuildInfo = { GuildRoster = function() end }
    _G.IsInRaid = function() return Stub.inRaid or false end
    _G.IsInGroup = function() return Stub.inRaid or false end
    _G.GetInstanceInfo = function() return "Testschlachtzug" end
    _G.C_PartyInfo = { GetLootMethod = function() return "group" end, InviteUnit = function() end }

    -- Addon-Kommunikation
    _G.C_ChatInfo = {
        RegisterAddonMessagePrefix = function() return true end,
        SendAddonMessage = function(prefix, msg, dist, target)
            table.insert(Stub.sentAddon, { prefix = prefix, msg = msg, dist = dist, target = target })
            return 0
        end,
        SendChatMessage = function(msg, chan) table.insert(Stub.sentChat, { msg = msg, chan = chan }) end,
    }

    -- Gegenstaende
    Stub.items = {
        [2770] = { name = "Kupfererz", quality = 1, type = "Handwerkswaren", class = 7, subclass = 7 },
        [2589] = { name = "Leinenstoff", quality = 1, type = "Handwerkswaren", class = 7, subclass = 5 },
        [19019] = { name = "Donnerzorn; Gesegnete Klinge", quality = 5, type = "Waffe", class = 2, subclass = 7 },
        [13444] = { name = "Großer Manatrank", quality = 1, type = "Verbrauchbar", class = 0, subclass = 1 },
    }
    local function ItemInfo(q)
        local id = tonumber(q) or tonumber(tostring(q):match("item:(%d+)"))
        local it = id and Stub.items[id]
        if not it then return nil end
        return it.name, Stub.Link(id), it.quality, 1, 1, it.type
    end
    -- GetItemInfoInstant: ohne Serverabfrage; fuer unbekannte Gegenstaende nil
    local function ItemInfoInstant(q)
        local id = tonumber(q) or tonumber(tostring(q):match("item:(%d+)"))
        local it = id and Stub.items[id]
        if not it or Stub.noInstant then return nil end
        return id, it.type, "Unterart", "", 134400, it.class, it.subclass
    end
    _G.C_Item = {
        GetItemInfo = ItemInfo,
        GetItemInfoInstant = ItemInfoInstant,
        GetItemQualityByID = function(id) local it = Stub.items[tonumber(id)] return it and it.quality end,
        GetItemIconByID = function(id) return 134400 end,
        RequestLoadItemDataByID = function() end,
    }
    -- Metadaten wie im Spiel aus der .toc
    _G.C_AddOns = { GetAddOnMetadata = function(_, key)
        local f = io.open("Grindkeep.toc")
        if not f then return nil end
        local toc = f:read("*a")
        f:close()
        return toc:match("## " .. key .. ":%s*([^\r\n]+)")
    end }
    _G.C_Container = {
        GetContainerNumSlots = function(bag) return Stub.bags[bag] and #Stub.bags[bag] or 0 end,
        GetContainerItemInfo = function(bag, slot)
            local s = Stub.bags[bag] and Stub.bags[bag][slot]
            if not s then return nil end
            return { stackCount = s.count, itemID = s.id, hyperlink = Stub.Link(s.id), quality = 1, isBound = s.bound or false }
        end,
    }
    Stub.bags = {}

    Stub.interface = forever and 16001 or 120100
    _G.GetBuildInfo = function() return forever and "1.16.1" or "12.1.0", "60000", "Okt 1 2026", Stub.interface end
    _G.GetItemInfoInstant = nil -- nur C_Item-Variante (beide Clients modern)

    if forever then
        -- In WoW Forever gemessen: die alten globalen Varianten gibt es nicht.
        _G.GetItemInfo = nil
        _G.GetItemIcon = nil
        _G.GetAddOnMetadata = nil
        _G.GetContainerItemInfo = nil
        _G.GetContainerNumSlots = nil
        _G.issecretvalue = nil
    else
        _G.issecretvalue = function() return false end
    end
    -- Nirgends mehr vorhanden: ein Aufruf ohne Pruefung faellt hier auf
    _G.SendChatMessage = nil
    _G.InviteUnit = nil
    _G.GuildRoster = nil

    -- Gildenbank
    Stub.bank = { tabs = { { name = "Erze", viewable = true }, { name = "Stoffe", viewable = true } }, logs = {}, money = {}, slots = {} }
    _G.MAX_GUILDBANK_TABS = 8
    _G.GetNumGuildBankTabs = function() return #Stub.bank.tabs end
    _G.GetGuildBankTabInfo = function(t)
        local tab = Stub.bank.tabs[t]
        if not tab then return nil end
        return tab.name, 136001, tab.viewable, true, 0, 0
    end
    _G.QueryGuildBankTabInfo = function() end
    _G.GetGuildBankMoney = function() return 22000000 end
    Stub.queries = {}
    _G.QueryGuildBankLog = function(t) table.insert(Stub.queries, { kind = "log", tab = t }) end
    _G.QueryGuildBankTab = function(t) table.insert(Stub.queries, { kind = "tab", tab = t }) end
    _G.GetGuildBankTransaction = function(tab, i)
        local e = Stub.bank.logs[tab] and Stub.bank.logs[tab][i]
        if not e then return nil end
        return e.type, e.name, Stub.Link(e.id), e.count, nil, nil, 0, 0, e.days or 0, e.hours or 0
    end
    _G.GetGuildBankMoneyTransaction = function(i)
        local e = Stub.bank.money[i]
        if not e then return nil end
        return e.type, e.name, e.amount, 0, 0, e.days or 0, e.hours or 0
    end
    _G.GetGuildBankItemInfo = function(tab, slot)
        local s = Stub.bank.slots[tab] and Stub.bank.slots[tab][slot]
        if not s then return nil, 0 end
        return 134400, s.count, false, false, 1
    end
    _G.GetGuildBankItemLink = function(tab, slot)
        local s = Stub.bank.slots[tab] and Stub.bank.slots[tab][slot]
        return s and Stub.Link(s.id) or nil
    end
end

function Stub.Link(id)
    if not id then return nil end
    local it = Stub.items[id]
    local name = it and it.name or ("Item" .. id)
    return "|cff1eff00|Hitem:" .. id .. "::::::::80:::::|h[" .. name .. "]|h|r"
end

-- Ereignis an alle Frames verteilen, die es registriert haben
function Stub.Fire(event, ...)
    for _, f in ipairs(Stub.frames) do
        if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
end

-- Alle anstehenden C_Timer-Rueckrufe ausfuehren (auch neu eingeplante)
function Stub.RunTimers()
    local guard = 0
    while #Stub.timers > 0 and guard < 1000 do
        guard = guard + 1
        local fn = table.remove(Stub.timers, 1)
        fn()
    end
end

-- OnUpdate aller Frames einmal mit elapsed Sekunden aufrufen
function Stub.Tick(elapsed)
    for _, f in ipairs(Stub.frames) do
        if f._scripts.OnUpdate then f._scripts.OnUpdate(f, elapsed) end
    end
end

-- Addon-Dateien in der Reihenfolge der .toc laden
function Stub.LoadAddon(root)
    local toc = assert(io.open(root .. "/Grindkeep.toc")):read("*a")
    local ns = {}
    local files = {}
    for line in toc:gmatch("[^\r\n]+") do
        if not line:match("^%s*#") and line:match("%.lua%s*$") then
            files[#files + 1] = line:match("^%s*(.-)%s*$")
        end
    end
    for _, file in ipairs(files) do
        local chunk = assert(loadfile(root .. "/" .. file))
        chunk("Grindkeep", ns)
    end
    return files
end

return Stub

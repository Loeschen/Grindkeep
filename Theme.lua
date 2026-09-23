--[[
    Grindkeep - Theme.lua

    Designs ("Skins") fuer das Hauptfenster und seine Seiten.

    Idee (angeregt von Skin-Addons wie AddOnSkins - nur die Idee, kein Code
    und keine Grafiken daraus): Jedes Element meldet beim Anlegen, WAS es
    ist ("Fenster", "Tafel", "Kachel", "Knopf", "Eingabefeld" ...), nicht
    wie es aussieht. Das Aussehen steht zentral in einer Design-Tabelle.
    Beim Umschalten wird alles Angemeldete neu eingefaerbt - ohne /reload.

    Designs:
      classic  Klassisch  - Blizzards Dialog- und Tooltip-Rahmen, Gold,
                            rote Blizzard-Knoepfe. Passt zu Classic/Forever.
      modern   Modern     - flach, dunkel, feine Linien, Akzent Gold.
      minimal  Minimal    - sehr dunkel, halbtransparent, schwarze 1-Pixel-
                            Raender, Akzent in Klassenfarbe (ElvUI-Stil).
      glass    Glas       - durchscheinend, helle feine Raender, Akzent Blau.

    Akzentfarbe: "Passend zum Design" oder fest (Gold, Klassenfarbe, Blau,
    Gruen, Lila, Rot). Sie faerbt aktive Reiter, Auswahl, Schalter.

    Blizzard-Vorlagen (rote Knoepfe, Eingabefelder, Schliessen-Kreuz) werden
    in den flachen Designs umgestaltet: deren Grafiken werden unsichtbar
    geschaltet und durch eine flache Flaeche ersetzt. Im klassischen Design
    bleiben sie unveraendert. Fehlt dafuer etwas auf einem Client
    (BackdropTemplateMixin), bleiben sie einfach wie sie sind.
]]

local DB = _G.GrindkeepDatabase
local L = _G.GrindkeepLocale

local Theme = {}
_G.GrindkeepTheme = Theme

local FLAT = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}

-- Blizzard-Dialogrand, aber mit einfarbigem Hintergrund: die Original-
-- Hintergrundgrafik ist halb durchsichtig, die Spielwelt schien durch.
local DIALOG = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local TOOLTIP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

-- ------------------------------------------------------------
-- Designs
-- Farben: { r, g, b, a }. "roles" beschreibt Hintergrund + Rand je Rolle.
-- ------------------------------------------------------------
Theme.List = { "classic", "modern", "minimal", "glass" }

Theme.Defs = {
    classic = {
        label = "THEME_CLASSIC",
        native = true, -- Blizzard-Knoepfe/-Felder unveraendert lassen
        accent = { 1, 0.82, 0, 1 },
        roles = {
            window  = { backdrop = DIALOG,  bg = { 0.05, 0.045, 0.04, 0.95 }, border = { 1, 1, 1, 1 } },
            panel   = { backdrop = TOOLTIP, bg = { 0, 0, 0, 0.55 },       border = { 0.6, 0.6, 0.65, 1 } },
            card    = { backdrop = TOOLTIP, bg = { 0.09, 0.07, 0.03, 0.8 }, border = { 0.78, 0.63, 0.28, 1 } },
            segment = { backdrop = FLAT,    bg = { 0.12, 0.1, 0.06, 0.85 }, border = { 0.42, 0.36, 0.22, 1 } },
            input   = { backdrop = FLAT,    bg = { 0, 0, 0, 0.6 },        border = { 0.45, 0.45, 0.5, 1 } },
            button  = { backdrop = FLAT,    bg = { 0.35, 0.05, 0.03, 1 }, border = { 0.78, 0.63, 0.28, 1 } },
        },
        colors = {
            title    = { 1, 0.82, 0, 1 },
            text     = { 1, 1, 1, 1 },
            textDim  = { 0.66, 0.64, 0.58, 1 },
            textMid  = { 0.85, 0.8, 0.65, 1 },
            line     = { 0.5, 0.42, 0.25, 0.8 },
            rowHover = { 1, 0.82, 0, 0.07 },
            rowSelect = { 1, 0.82, 0, 0.14 },
        },
    },
    modern = {
        label = "THEME_MODERN",
        accent = { 0.79, 0.64, 0.15, 1 },
        roles = {
            window  = { backdrop = FLAT, bg = { 0.07, 0.07, 0.085, 0.96 }, border = { 0.18, 0.19, 0.22, 1 } },
            panel   = { backdrop = FLAT, bg = { 0.095, 0.095, 0.115, 0.96 }, border = { 0.17, 0.18, 0.21, 1 } },
            card    = { backdrop = FLAT, bg = { 0.12, 0.12, 0.145, 0.96 }, border = { 0.2, 0.21, 0.25, 1 } },
            segment = { backdrop = FLAT, bg = { 1, 1, 1, 0.04 },  border = { 0.2, 0.21, 0.25, 1 } },
            input   = { backdrop = FLAT, bg = { 0, 0, 0, 0.45 },  border = { 0.24, 0.25, 0.29, 1 } },
            button  = { backdrop = FLAT, bg = { 1, 1, 1, 0.06 },  border = { 0.26, 0.27, 0.32, 1 } },
        },
        colors = {
            title    = "accent",
            text     = { 0.93, 0.93, 0.95, 1 },
            textDim  = { 0.55, 0.55, 0.6, 1 },
            textMid  = { 0.75, 0.75, 0.8, 1 },
            line     = { 0.18, 0.19, 0.22, 1 },
            rowHover = { 1, 1, 1, 0.05 },
            rowSelect = "accent:0.14",
        },
    },
    minimal = {
        label = "THEME_MINIMAL",
        accent = "class",
        roles = {
            window  = { backdrop = FLAT, bg = { 0.04, 0.04, 0.04, 0.85 }, border = { 0, 0, 0, 1 } },
            panel   = { backdrop = FLAT, bg = { 0.08, 0.08, 0.08, 0.7 },  border = { 0, 0, 0, 1 } },
            card    = { backdrop = FLAT, bg = { 0.11, 0.11, 0.11, 0.75 }, border = { 0, 0, 0, 1 } },
            segment = { backdrop = FLAT, bg = { 0.12, 0.12, 0.12, 0.8 },  border = { 0, 0, 0, 1 } },
            input   = { backdrop = FLAT, bg = { 0.02, 0.02, 0.02, 0.8 },  border = { 0, 0, 0, 1 } },
            button  = { backdrop = FLAT, bg = { 0.14, 0.14, 0.14, 0.9 },  border = { 0, 0, 0, 1 } },
        },
        colors = {
            title    = "accent",
            text     = { 0.95, 0.95, 0.95, 1 },
            textDim  = { 0.5, 0.5, 0.5, 1 },
            textMid  = { 0.78, 0.78, 0.78, 1 },
            line     = { 0, 0, 0, 1 },
            rowHover = { 1, 1, 1, 0.06 },
            rowSelect = "accent:0.18",
        },
    },
    glass = {
        label = "THEME_GLASS",
        accent = { 0.35, 0.75, 1, 1 },
        roles = {
            window  = { backdrop = FLAT, bg = { 0.05, 0.07, 0.11, 0.8 },  border = { 1, 1, 1, 0.22 } },
            panel   = { backdrop = FLAT, bg = { 0.1, 0.13, 0.18, 0.35 }, border = { 1, 1, 1, 0.1 } },
            card    = { backdrop = FLAT, bg = { 1, 1, 1, 0.07 },  border = { 1, 1, 1, 0.14 } },
            segment = { backdrop = FLAT, bg = { 1, 1, 1, 0.05 },  border = { 1, 1, 1, 0.14 } },
            input   = { backdrop = FLAT, bg = { 0, 0, 0, 0.3 },   border = { 1, 1, 1, 0.18 } },
            button  = { backdrop = FLAT, bg = { 1, 1, 1, 0.08 },  border = { 1, 1, 1, 0.2 } },
        },
        colors = {
            title    = { 1, 1, 1, 1 },
            text     = { 1, 1, 1, 1 },
            textDim  = { 0.72, 0.78, 0.86, 1 },
            textMid  = { 0.86, 0.9, 0.95, 1 },
            line     = { 1, 1, 1, 0.14 },
            rowHover = { 1, 1, 1, 0.07 },
            rowSelect = "accent:0.2",
        },
    },
}

Theme.Accents = {
    { key = "theme",  label = "ACCENT_THEME" },
    { key = "gold",   label = "ACCENT_GOLD",   color = { 1, 0.82, 0, 1 } },
    { key = "class",  label = "ACCENT_CLASS" },
    { key = "blue",   label = "ACCENT_BLUE",   color = { 0.25, 0.62, 1, 1 } },
    { key = "green",  label = "ACCENT_GREEN",  color = { 0.18, 0.8, 0.44, 1 } },
    { key = "purple", label = "ACCENT_PURPLE", color = { 0.66, 0.47, 0.96, 1 } },
    { key = "red",    label = "ACCENT_RED",    color = { 0.92, 0.32, 0.26, 1 } },
}

-- ------------------------------------------------------------
-- Aktuelles Design und Farben
-- ------------------------------------------------------------
local function ClassColor()
    local class = UnitClass and select(2, UnitClass("player"))
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return { c.r, c.g, c.b, 1 } end
    return { 1, 0.82, 0, 1 }
end

function Theme.Key()
    local key = DB.GetSetting("theme")
    if not Theme.Defs[key] then key = "classic" end
    return key
end

function Theme.Current()
    return Theme.Defs[Theme.Key()]
end

function Theme.Accent()
    local choice = DB.GetSetting("accent") or "theme"
    for _, a in ipairs(Theme.Accents) do
        if a.key == choice and choice ~= "theme" then
            if choice == "class" then return ClassColor() end
            return a.color
        end
    end
    local t = Theme.Current().accent
    if t == "class" then return ClassColor() end
    return t
end

-- Farbe nach Name: "accent", "title", "text", "textDim", "textMid", "line",
-- "rowHover", "rowSelect", "accentFill" oder eine Rolle wie "panel.border".
function Theme.Color(name)
    local t = Theme.Current()
    if name == "accent" then return Theme.Accent() end
    if name == "accentFill" then
        local a = Theme.Accent()
        return { a[1], a[2], a[3], 0.22 }
    end
    local role, part = name:match("^(%a+)%.(%a+)$")
    if role and t.roles[role] then return t.roles[role][part] or { 1, 1, 1, 1 } end
    local c = t.colors[name]
    if c == "accent" then return Theme.Accent() end
    if type(c) == "string" then
        local alpha = tonumber(c:match("^accent:([%d%.]+)$"))
        if alpha then
            local a = Theme.Accent()
            return { a[1], a[2], a[3], alpha }
        end
    end
    return c or { 1, 1, 1, 1 }
end

function Theme.Hex(name)
    local c = Theme.Color(name)
    return string.format("|cff%02x%02x%02x", math.floor(c[1] * 255), math.floor(c[2] * 255), math.floor(c[3] * 255))
end

-- ------------------------------------------------------------
-- Anmelden und Einfaerben
-- ------------------------------------------------------------
local skinned = {}   -- { obj, kind, key }
local listeners = {} -- Funktionen, die nach einem Wechsel laufen

local CLOSE_ROLE = { backdrop = FLAT, bg = { 0, 0, 0, 0 }, border = { 0, 0, 0, 0 } }

local function ApplyBackdrop(frame, role)
    if not frame.SetBackdrop then return end
    local r = (role == "close" and CLOSE_ROLE) or Theme.Current().roles[role] or Theme.Current().roles.panel
    pcall(frame.SetBackdrop, frame, r.backdrop)
    if frame.SetBackdropColor then frame:SetBackdropColor(unpack(r.bg)) end
    if frame.SetBackdropBorderColor then frame:SetBackdropBorderColor(unpack(r.border)) end
end

-- Knopf/Eingabefeld/Kreuz einer Blizzard-Vorlage: deren Grafiken
local function TemplateTextures(obj)
    local list = {}
    for _, key in ipairs({ "Left", "Middle", "Right", "Mid" }) do
        local r = rawget(obj, key)
        if type(r) == "table" and r.SetAlpha then table.insert(list, r) end
    end
    for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
        if obj[getter] then
            local ok, tex = pcall(obj[getter], obj)
            if ok and type(tex) == "table" and tex.SetAlpha then table.insert(list, tex) end
        end
    end
    return list
end

local function EnsureBackdrop(obj)
    if obj.SetBackdrop then return true end
    if not (Mixin and BackdropTemplateMixin) then return false end
    Mixin(obj, BackdropTemplateMixin)
    obj.gkMixedBackdrop = true
    if obj.HookScript and obj.OnBackdropSizeChanged then
        obj:HookScript("OnSizeChanged", obj.OnBackdropSizeChanged)
    end
    return true
end

local function ApplyTemplateSkin(obj, role)
    local flat = not Theme.Current().native
    if flat and not EnsureBackdrop(obj) then flat = false end
    for _, tex in ipairs(TemplateTextures(obj)) do tex:SetAlpha(flat and 0 or 1) end
    if flat then
        ApplyBackdrop(obj, role)
    elseif obj.gkMixedBackdrop and obj.SetBackdrop then
        pcall(obj.SetBackdrop, obj, nil) -- zurueck zum reinen Blizzard-Aussehen
    end
    if role == "input" and obj.SetTextInsets then
        if flat then obj:SetTextInsets(6, 6, 0, 0) else obj:SetTextInsets(0, 0, 0, 0) end
    end
    if role == "close" and obj.gkX then obj.gkX:SetShown(flat) end
end

local function Apply(entry)
    local obj, kind, key = entry[1], entry[2], entry[3]
    if kind == "backdrop" then
        ApplyBackdrop(obj, key)
    elseif kind == "texture" then
        if obj.SetColorTexture then obj:SetColorTexture(unpack(Theme.Color(key))) end
    elseif kind == "text" then
        if obj.SetTextColor then obj:SetTextColor(unpack(Theme.Color(key))) end
    elseif kind == "template" then
        ApplyTemplateSkin(obj, key)
    end
end

local function Register(obj, kind, key)
    if not obj then return obj end
    local entry = { obj, kind, key }
    table.insert(skinned, entry)
    pcall(Apply, entry)
    return obj
end

-- Rahmen/Hintergrund einer eigenen Flaeche (BackdropTemplate)
function Theme.Skin(frame, role) return Register(frame, "backdrop", role) end
-- Farbflaeche (Linie, Hover, Auswahl)
function Theme.Tint(texture, colorName) return Register(texture, "texture", colorName) end
-- Textfarbe
function Theme.TextColor(fontString, colorName) return Register(fontString, "text", colorName) end

-- Blizzard-Knopf (UIPanelButtonTemplate)
function Theme.SkinButton(btn)
    if not btn or btn.gkSkinned then return btn end
    btn.gkSkinned = true
    if btn.HookScript then
        btn:HookScript("OnEnter", function(self)
            if not Theme.Current().native and self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(unpack(Theme.Accent()))
            end
        end)
        btn:HookScript("OnLeave", function(self)
            if not Theme.Current().native and self.SetBackdropBorderColor then
                self:SetBackdropBorderColor(unpack(Theme.Current().roles.button.border))
            end
        end)
    end
    return Register(btn, "template", "button")
end

-- Blizzard-Eingabefeld (InputBoxTemplate)
function Theme.SkinInput(box)
    if not box or box.gkSkinned then return box end
    box.gkSkinned = true
    return Register(box, "template", "input")
end

-- Blizzard-Schliessen-Kreuz (UIPanelCloseButton)
function Theme.SkinClose(btn)
    if not btn or btn.gkSkinned then return btn end
    btn.gkSkinned = true
    if btn.CreateFontString then
        btn.gkX = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        btn.gkX:SetPoint("CENTER", 0, 0)
        btn.gkX:SetText("X")
        btn.gkX:Hide()
        if btn.HookScript then
            btn:HookScript("OnEnter", function(self) if self.gkX then self.gkX:SetTextColor(1, 0.35, 0.3) end end)
            btn:HookScript("OnLeave", function(self) if self.gkX then self.gkX:SetTextColor(unpack(Theme.Color("textMid"))) end end)
        end
        Register(btn.gkX, "text", "textMid")
    end
    btn.gkCloseOnly = true
    return Register(btn, "template", "close")
end

-- Alle Blizzard-Knoepfe und -Eingabefelder unterhalb eines Rahmens
-- (fuer die eingebetteten Seiten Vorgaenge/Bestand/Loot).
function Theme.SkinTree(frame, depth)
    depth = depth or 1
    if not frame or depth > 8 or not frame.GetChildren then return end
    for _, child in ipairs({ frame:GetChildren() }) do
        if type(child) == "table" and child.GetObjectType then
            local ok, t = pcall(child.GetObjectType, child)
            local hasParts = rawget(child, "Left") and rawget(child, "Right")
            if ok and t == "Button" and hasParts then
                Theme.SkinButton(child)
            elseif ok and t == "EditBox" and hasParts then
                Theme.SkinInput(child)
            end
            Theme.SkinTree(child, depth + 1)
        end
    end
end

function Theme.OnChange(fn) table.insert(listeners, fn) end

function Theme.ApplyAll()
    for _, entry in ipairs(skinned) do pcall(Apply, entry) end
    for _, fn in ipairs(listeners) do pcall(fn) end
end

function Theme.Set(key)
    if not Theme.Defs[key] then return false end
    DB.SetSetting("theme", key)
    Theme.ApplyAll()
    return true
end

function Theme.SetAccent(key)
    for _, a in ipairs(Theme.Accents) do
        if a.key == key then
            DB.SetSetting("accent", key)
            Theme.ApplyAll()
            return true
        end
    end
    return false
end

-- Nur fuer Tests
Theme._skinned = skinned

--[[
    Grindkeep - Options.lua

    Registriert Grindkeep im nativen Blizzard-Optionsfenster (Spielmenue ->
    Optionen -> AddOns), im selben Stil wie das Schwester-Addon Grindstone:
    Settings.RegisterVerticalLayoutCategory statt eines Eigenbau-Fensters.
    Jede einzelne Checkbox-/Regler-Registrierung ist per pcall abgesichert,
    damit ein einzelner, nicht unterstuetzter Settings-Aufruf hoechstens
    diesen einen Eintrag ausfallen laesst statt das ganze Fenster.
]]
local ADDON_NAME = ...
local DB = _G.GrindkeepDatabase
local L = _G.GrindkeepLocale

local OptionsCategory = nil

local function AddSectionHeader(layout, text)
    if not (CreateSettingsListSectionHeaderInitializer and layout and layout.AddInitializer) then
        return
    end
    local ok, initializer = pcall(CreateSettingsListSectionHeaderInitializer, text)
    if ok and initializer then
        layout:AddInitializer(initializer)
    end
end

local function AddCheckbox(category, variable, name, tooltip, getter, setter, default)
    local ok, setting = pcall(
        Settings.RegisterProxySetting,
        category,
        variable,
        Settings.VarType and Settings.VarType.Boolean or "boolean",
        name,
        default,
        getter,
        setter
    )
    if ok and setting then
        pcall(Settings.CreateCheckbox, category, setting, tooltip)
    end
    return ok and setting or nil
end

local function AddSlider(category, variable, name, tooltip, minValue, maxValue, step, default, getter, setter, formatter)
    local ok, setting = pcall(
        Settings.RegisterProxySetting,
        category,
        variable,
        Settings.VarType and Settings.VarType.Number or "number",
        name,
        default,
        getter,
        setter
    )
    if not (ok and setting) then return nil end

    local optOk, options = pcall(Settings.CreateSliderOptions, minValue, maxValue, step)
    if optOk and options and options.SetLabelFormatter and MinimalSliderWithSteppersMixin then
        pcall(options.SetLabelFormatter, options, MinimalSliderWithSteppersMixin.Label.Right, formatter)
    end
    if optOk and options then
        pcall(Settings.CreateSlider, category, setting, options, tooltip)
    end
    return setting
end

local function RegisterOptions()
    if OptionsCategory then return end
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then
        -- Ohne native Settings-API bleibt Grindkeep rein slash-command-
        -- gesteuert (siehe Core.lua), statt mit einem riskanten Eigenbau-
        -- Fenster ohne Scroll-Absicherung.
        return
    end

    local ok, category, layout = pcall(Settings.RegisterVerticalLayoutCategory, ADDON_NAME)
    if not ok or not category then return end
    OptionsCategory = category

    ------------------------------------------------------------------
    -- Scannen
    ------------------------------------------------------------------
    AddSectionHeader(layout, L["OPT_SECTION_SCAN"])

    AddCheckbox(category, "grindkeep_autoScanOnOpen", L["OPT_AUTOSCAN_LABEL"],
        L["OPT_AUTOSCAN_TOOLTIP"],
        function() return DB.GetSetting("autoScanOnOpen") end,
        function(value) DB.SetSetting("autoScanOnOpen", value) end,
        DB.SettingDefaults.autoScanOnOpen)

    AddCheckbox(category, "grindkeep_scanChatMessages", L["OPT_SCAN_CHAT_LABEL"],
        L["OPT_SCAN_CHAT_TOOLTIP"],
        function() return DB.GetSetting("scanChatMessages") end,
        function(value) DB.SetSetting("scanChatMessages", value) end,
        DB.SettingDefaults.scanChatMessages)

    AddCheckbox(category, "grindkeep_autoStockScan", L["OPT_AUTOSTOCK_LABEL"],
        L["OPT_AUTOSTOCK_TOOLTIP"],
        function() return DB.GetSetting("autoStockScan") end,
        function(value) DB.SetSetting("autoStockScan", value) end,
        DB.SettingDefaults.autoStockScan)

    ------------------------------------------------------------------
    -- Bedienung (Minimap-Knopf, Reiter im Gildenbank-Fenster)
    ------------------------------------------------------------------
    AddSectionHeader(layout, L["OPT_SECTION_ACCESS"])

    AddCheckbox(category, "grindkeep_showMinimapButton", L["OPT_MINIMAP_LABEL"],
        L["OPT_MINIMAP_TOOLTIP"],
        function() return DB.GetSetting("showMinimapButton") end,
        function(value)
            DB.SetSetting("showMinimapButton", value)
            -- sofort wirksam, ohne Neuladen
            if _G.GrindkeepUI and _G.GrindkeepUI.SetMinimapButtonShown then
                _G.GrindkeepUI.SetMinimapButtonShown(value)
            end
        end,
        DB.SettingDefaults.showMinimapButton)

    AddCheckbox(category, "grindkeep_showBankTabButton", L["OPT_BANKTAB_LABEL"],
        L["OPT_BANKTAB_TOOLTIP"],
        function() return DB.GetSetting("showBankTabButton") end,
        function(value)
            DB.SetSetting("showBankTabButton", value)
            if _G.GrindkeepUI and _G.GrindkeepUI.SetBankTabShown then
                _G.GrindkeepUI.SetBankTabShown()
            end
        end,
        DB.SettingDefaults.showBankTabButton)

    ------------------------------------------------------------------
    -- Aussehen: Schriftart, Schriftgroesse, Deckkraft
    --
    -- Die Schriftauswahl braucht ein Auswahlmenue. Diese Settings-API
    -- ist die unsicherste von allen hier verwendeten (Checkboxen und
    -- Regler sind im Spiel bestaetigt, ein Dropdown noch nicht) -
    -- deshalb wie ueberall per pcall abgesichert. Faellt es aus, bleibt
    -- der Slash-Befehl "/gkeep style font <name>" als voller Ersatz.
    ------------------------------------------------------------------
    AddSectionHeader(layout, L["OPT_SECTION_STYLE"])

    if _G.GrindkeepStyle and Settings and Settings.CreateDropdown then
        local fontSetting = nil
        local okSetting, setting = pcall(
            Settings.RegisterProxySetting,
            category,
            "grindkeep_fontChoice",
            Settings.VarType and Settings.VarType.String or "string",
            L["OPT_FONT_LABEL"],
            DB.SettingDefaults.fontChoice,
            function() return DB.GetSetting("fontChoice") end,
            function(value)
                DB.SetSetting("fontChoice", value)
                _G.GrindkeepStyle.Apply()
            end
        )
        if okSetting then fontSetting = setting end

        if fontSetting then
            if Settings.CreateControlTextContainer then
                pcall(Settings.CreateDropdown, category, fontSetting, function()
                    local container = Settings.CreateControlTextContainer()
                    for _, f in ipairs(_G.GrindkeepStyle.Fonts) do
                        container:Add(f.key, L[f.label])
                    end
                    return container:GetData()
                end, L["OPT_FONT_TOOLTIP"])
            end
        end
    end

    -- Design und Akzentfarbe (auch ueber das Zahnrad im Hauptfenster)
    local Theme = _G.GrindkeepTheme
    local function AddChoice(variable, label, tooltip, settingKey, entries, apply)
        if not (Theme and Settings and Settings.CreateDropdown and Settings.CreateControlTextContainer) then return end
        local ok, setting = pcall(Settings.RegisterProxySetting, category, variable,
            Settings.VarType and Settings.VarType.String or "string", label,
            DB.SettingDefaults[settingKey],
            function() return DB.GetSetting(settingKey) end,
            function(value) apply(value) end)
        if not ok or not setting then return end
        pcall(Settings.CreateDropdown, category, setting, function()
            local container = Settings.CreateControlTextContainer()
            for _, e in ipairs(entries) do container:Add(e.key, e.label) end
            return container:GetData()
        end, tooltip)
    end
    if Theme then
        local themes = {}
        for _, key in ipairs(Theme.List) do table.insert(themes, { key = key, label = L[Theme.Defs[key].label] }) end
        AddChoice("grindkeep_theme", L["OPT_THEME_LABEL"], L["OPT_THEME_TOOLTIP"], "theme", themes, Theme.Set)
        local accents = {}
        for _, a in ipairs(Theme.Accents) do table.insert(accents, { key = a.key, label = L[a.label] }) end
        AddChoice("grindkeep_accent", L["OPT_ACCENT_LABEL"], L["OPT_ACCENT_TOOLTIP"], "accent", accents, Theme.SetAccent)
    end

    AddSlider(category, "grindkeep_fontScale", L["OPT_FONTSIZE_LABEL"],
        L["OPT_FONTSIZE_TOOLTIP"],
        70, 160, 5,
        100,
        function() return (tonumber(DB.GetSetting("fontScale")) or 1) * 100 end,
        function(value)
            DB.SetSetting("fontScale", value / 100)
            if _G.GrindkeepStyle then _G.GrindkeepStyle.Apply() end
        end,
        function(value) return string.format("%d%%", math.floor(value)) end)

    AddSlider(category, "grindkeep_windowOpacity", L["OPT_OPACITY_LABEL"],
        L["OPT_OPACITY_TOOLTIP"],
        30, 100, 5,
        100,
        function() return (tonumber(DB.GetSetting("windowOpacity")) or 1) * 100 end,
        function(value)
            DB.SetSetting("windowOpacity", value / 100)
            if _G.GrindkeepStyle then _G.GrindkeepStyle.Apply() end
        end,
        function(value) return string.format("%d%%", math.floor(value)) end)

    ------------------------------------------------------------------
    -- Twink-Zuordnung mit der Gilde abgleichen
    ------------------------------------------------------------------
    AddSectionHeader(layout, L["OPT_SECTION_TWINKSYNC"])

    AddCheckbox(category, "grindkeep_syncEnabled", L["OPT_SYNC_ENABLED_LABEL"],
        L["OPT_SYNC_ENABLED_TOOLTIP"],
        function() return DB.GetSetting("syncEnabled") end,
        function(value) DB.SetSetting("syncEnabled", value) end,
        DB.SettingDefaults.syncEnabled)

    AddSlider(category, "grindkeep_syncTrustedRank", L["OPT_TRUST_RANK_LABEL"],
        L["OPT_TRUST_RANK_TOOLTIP"],
        0, 9, 1,
        DB.SettingDefaults.syncTrustedRank,
        function() return DB.GetSetting("syncTrustedRank") end,
        function(value) DB.SetSetting("syncTrustedRank", value) end,
        function(value) return string.format(L["OPT_RANK_FORMAT"], math.floor(value)) end)

    ------------------------------------------------------------------
    -- Loot-Tracking
    ------------------------------------------------------------------
    AddSectionHeader(layout, L["OPT_SECTION_LOOT"])

    AddCheckbox(category, "grindkeep_lootTrackingEnabled", L["OPT_LOOT_ENABLED_LABEL"],
        L["OPT_LOOT_ENABLED_TOOLTIP"],
        function() return DB.GetSetting("lootTrackingEnabled") end,
        function(value)
            DB.SetSetting("lootTrackingEnabled", value)
            -- Loot-Knopf im Hauptfenster ein-/ausblenden
            if _G.GrindkeepUI and _G.GrindkeepUI.LayoutHeaderButtons then
                _G.GrindkeepUI.LayoutHeaderButtons()
            end
        end,
        DB.SettingDefaults.lootTrackingEnabled)

    AddCheckbox(category, "grindkeep_lootRaidOnly", L["OPT_LOOT_RAIDONLY_LABEL"],
        L["OPT_LOOT_RAIDONLY_TOOLTIP"],
        function() return DB.GetSetting("lootRaidOnly") end,
        function(value) DB.SetSetting("lootRaidOnly", value) end,
        DB.SettingDefaults.lootRaidOnly)

    AddCheckbox(category, "grindkeep_lootSyncEnabled", L["OPT_LOOT_SYNC_LABEL"],
        L["OPT_LOOT_SYNC_TOOLTIP"],
        function() return DB.GetSetting("lootSyncEnabled") end,
        function(value) DB.SetSetting("lootSyncEnabled", value) end,
        DB.SettingDefaults.lootSyncEnabled)

    local QUALITY_NAMES = {
        [0] = L["OPT_QUALITY_0"], [1] = L["OPT_QUALITY_1"], [2] = L["OPT_QUALITY_2"],
        [3] = L["OPT_QUALITY_3"], [4] = L["OPT_QUALITY_4"], [5] = L["OPT_QUALITY_5"],
    }
    AddSlider(category, "grindkeep_lootMinQuality", L["OPT_LOOT_MINQ_LABEL"],
        L["OPT_LOOT_MINQ_TOOLTIP"],
        0, 5, 1,
        DB.SettingDefaults.lootMinQuality,
        function() return DB.GetSetting("lootMinQuality") end,
        function(value) DB.SetSetting("lootMinQuality", value) end,
        function(value) return QUALITY_NAMES[math.floor(value)] or tostring(math.floor(value)) end)

    ------------------------------------------------------------------
    -- Gespeicherte Daten: Aufbewahrungsdauer
    -- Regler in Monaten (0 = immer behalten), gespeichert in Tagen.
    ------------------------------------------------------------------
    AddSectionHeader(layout, L["OPT_SECTION_DATA"])

    AddSlider(category, "grindkeep_retentionMonths", L["OPT_RETENTION_LABEL"],
        L["OPT_RETENTION_TOOLTIP"],
        0, 36, 1,
        12,
        function()
            local days = tonumber(DB.GetSetting("retentionDays")) or 0
            return math.floor(days * 12 / 365 + 0.5)
        end,
        function(value)
            local months = math.floor(value + 0.5)
            DB.SetSetting("retentionDays", months == 0 and 0 or math.floor(months * 365 / 12 + 0.5))
        end,
        function(value)
            local months = math.floor(value + 0.5)
            if months == 0 then return L["OPT_RETENTION_FOREVER"] end
            return string.format(L["OPT_RETENTION_FORMAT"], months)
        end)

    pcall(Settings.RegisterAddOnCategory, category)
end

-- Erst nach PLAYER_LOGIN registrieren (gleiches Vorgehen wie bei Grindstone) -
-- zu diesem Zeitpunkt sind alle Settings-Sub-APIs sicher verfuegbar.
local frame = CreateFrame("Frame")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent", function()
    RegisterOptions()
end)

_G.GrindkeepOptions = {
    OpenToCategory = function()
        if OptionsCategory and OptionsCategory.ID then
            Settings.OpenToCategory(OptionsCategory.ID)
            return true
        end
        return false
    end,
}

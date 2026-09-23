--[[
    Grindkeep - Locale.lua

    Einfache, abhaengigkeitsfreie Lokalisierung (kein AceLocale-3.0, siehe
    Erklaerung fuer diese Haltung z.B. bei der kleinen Eigenbau-Base64-
    Implementierung in Comm.lua: fuer diesen Textumfang reicht eine simple
    Tabelle, ohne eine weitere Abhaengigkeit einzufuehren). Englisch ist
    die Standardsprache (Blizzards eigene Konvention und der ueberwiegende
    Teil des CurseForge-Publikums), Deutsch wird automatisch verwendet,
    wenn der Client auf "deDE" steht.

    MUSS als ERSTE Datei geladen werden (siehe Grindkeep.toc), da so gut
    wie jede andere Datei _G.GrindkeepLocale fuer sichtbaren Text
    verwendet. Anders als bei Emberstone (das per lokalem vararg-"Addon"-
    Tabelle arbeitet) nutzt Grindkeep durchgaengig eigene globale Tabellen
    (_G.GrindkeepDatabase, _G.GrindkeepComm, _G.GrindkeepUI, ...) - aus
    demselben Grund wird auch die Locale-Tabelle hier als eigener Global
    exponiert, statt an eine gemeinsame Addon-Tabelle anzuhaengen.

    Faellt ein Schluessel in der aktuellen Sprache aus (Tippfehler, neuer
    Schluessel ohne Uebersetzung), liefert L[key] automatisch Englisch
    zurueck statt eines Lua-Fehlers oder eines leeren Strings.

    WICHTIG: %s/%d muessen in enUS und deDE in EXAKT derselben Reihenfolge
    auftreten - der Aufrufer uebergibt die Argumente einmal, unabhaengig
    von der Sprache (Lua's string.format kennt keine positionalen %n$-
    Platzhalter). Alle Zeilen unten wurden entsprechend geprueft.
]]

local locale = (GetLocale() == "deDE") and "deDE" or "enUS"

local STRINGS = {
    -- ============================================================
    -- Core.lua
    -- ============================================================
    CORE_LOADED = {
        enUS = "loaded. /gkeep for commands, /gkeep (no argument) toggles the window.",
        deDE = "geladen. /gkeep für Befehle, /gkeep (ohne Argument) öffnet das Fenster.",
    },
    CORE_ERR_TAB = {
        enUS = "Error at tab %d, index %d: %s",
        deDE = "Fehler bei Tab %d, Index %d: %s",
    },
    CORE_ERR_MONEYLOG = {
        enUS = "Error in the money log, index %d: %s",
        deDE = "Fehler beim Geld-Log, Index %d: %s",
    },
    CORE_SCAN_DONE = {
        enUS = "Scan complete. %d new entries saved.",
        deDE = "Scan abgeschlossen. %d neue Einträge gespeichert.",
    },
    CORE_NOT_IN_GUILD = { enUS = "You are not in a guild.", deDE = "Du bist in keiner Gilde." },
    CORE_SCAN_RUNNING = { enUS = "A scan is already running.", deDE = "Es läuft bereits ein Scan." },
    CORE_API_MISSING = {
        enUS = "CRITICAL: The guild bank API no longer exists in this build.",
        deDE = "KRITISCH: Die Gildenbank-API existiert in diesem Build nicht (mehr).",
    },
    CORE_SCAN_START = {
        enUS = "Starting scan across %d tab(s) + money log ...",
        deDE = "Starte Scan über %d Tab(s) + Geld-Log ...",
    },
    CORE_TIMEOUT = {
        enUS = "Timeout at %s - proceeding with the current data.",
        deDE = "Zeitüberschreitung bei %s - verarbeite mit aktuellem Stand weiter.",
    },
    CORE_TIMEOUT_TAB = { enUS = "Tab %d", deDE = "Tab %d" },
    CORE_TIMEOUT_MONEYLOG = { enUS = "Money Log", deDE = "Geld-Log" },
    CORE_LIST_EMPTY = {
        enUS = "No data recorded yet (opening the guild bank triggers a scan, or use /gkeep scan).",
        deDE = "Noch keine Daten erfasst (Gildenbank öffnen löst einen Scan aus, oder /gkeep scan).",
    },
    CORE_LIST_HEADER = { enUS = "Player list (sorted by %s):", deDE = "Spielerliste (sortiert nach %s):" },
    CORE_LIST_ROW = {
        enUS = "%s: Net %s | Items in %d / out %d",
        deDE = "%s: Netto %s | Items ein %d / aus %d",
    },
    CORE_DETAILS_NONE = { enUS = "No data for %s.", deDE = "Keine Daten für %s." },
    CORE_IS_TWINK_OF = { enUS = "%s is an alt of %s.", deDE = "%s ist Twink von %s." },
    CORE_HAS_TWINKS = { enUS = "%s has the following alts: %s", deDE = "%s hat folgende Twinks: %s" },
    CORE_OWN_BALANCE = {
        enUS = "Own balance: Gold in %s | out %s | Items in %d / out %d",
        deDE = "Eigene Bilanz: Gold ein %s | aus %s | Items ein %d / aus %d",
    },
    CORE_AGGREGATED = {
        enUS = "Aggregated (main+alts): Gold in %s | out %s | Net %s",
        deDE = "Aggregiert (Main+Twinks): Gold ein %s | aus %s | Netto %s",
    },
    CORE_TX_NEED_NAME = {
        enUS = "Please provide a name: /gkeep tx <Name> [gold|item]",
        deDE = "Bitte Namen angeben: /gkeep tx <Name> [gold|item]",
    },
    CORE_TX_NONE = { enUS = "No transactions for %s (filter: %s).", deDE = "Keine Transaktionen für %s (Filter: %s)." },
    CORE_FILTER_ALL = { enUS = "all", deDE = "alle" },
    CORE_TX_HEADER = { enUS = "Recent transactions from %s:", deDE = "Letzte Transaktionen von %s:" },
    CORE_TX_GOLD_LINE = { enUS = "[Gold] %s %s", deDE = "[Gold] %s %s" },
    CORE_TX_ITEM_LINE = { enUS = "[Item, Tab %s] %s %dx %s", deDE = "[Item, Tab %s] %s %dx %s" },
    CORE_ITEM_INFO_PENDING = { enUS = "? (item info pending)", deDE = "? (Item-Info folgt)" },
    CORE_GOLD_FORMAT = { enUS = "%dG %dS %dC", deDE = "%dG %dS %dK" },
    CORE_HELP_HEADER = { enUS = "Commands:", deDE = "Befehle:" },
    CORE_HELP_TOGGLE = {
        enUS = "/gkeep                    - toggle window (if the UI is loaded)",
        deDE = "/gkeep                    - Fenster ein-/ausblenden (falls UI geladen)",
    },
    CORE_HELP_OPTIONS = {
        enUS = "/gkeep options            - open settings (also available via Options -> AddOns -> Grindkeep)",
        deDE = "/gkeep options            - Einstellungen öffnen (auch über Optionen -> AddOns -> Grindkeep erreichbar)",
    },
    CORE_HELP_SCAN = {
        enUS = "/gkeep scan               - trigger a scan manually (guild bank must be open)",
        deDE = "/gkeep scan               - Scan manuell anstoßen (Gildenbank muss geöffnet sein)",
    },
    CORE_HELP_LIST = {
        enUS = "/gkeep list [net|deposits|activity|name] - player list",
        deDE = "/gkeep list [net|deposits|activity|name] - Spielerliste",
    },
    CORE_HELP_PLAYER = {
        enUS = "/gkeep player <Name>      - details for a person (incl. alts)",
        deDE = "/gkeep player <Name>      - Details zu einer Person (inkl. Twinks)",
    },
    CORE_HELP_TX = {
        enUS = "/gkeep tx <Name> [gold|item] - recent transactions for a person",
        deDE = "/gkeep tx <Name> [gold|item] - letzte Transaktionen einer Person",
    },
    CORE_HELP_ALT = {
        enUS = "/gkeep alt <alt> = <main> - assign an alt (the \"=\" also allows names with spaces; shared with the guild if your rank allows)",
        deDE = "/gkeep alt <Twink> = <Main> - Twink zuordnen (mit \"=\" auch für Namen mit Leerzeichen; wird an die Gilde verteilt, wenn der Rang reicht)",
    },
    CORE_HELP_LOOT_CHECK = {
        enUS = "/gkeep loot check <Item>  - shows who an item has already been awarded to",
        deDE = "/gkeep loot check <Item>  - zeigt, an wen ein Item bereits vergeben wurde",
    },
    CORE_HELP_LOOT_RECENT = {
        enUS = "/gkeep loot recent [n]    - last n loot entries (default 15)",
        deDE = "/gkeep loot recent [n]    - letzte n Loot-Einträge (Standard 15)",
    },
    CORE_HELP_LOOT_UI = {
        enUS = "/gkeep loot ui            - open the loot search window",
        deDE = "/gkeep loot ui            - Loot-Suchfenster öffnen",
    },
    CORE_HELP_LOOT_STATS = {
        enUS = "/gkeep loot stats         - open the loot window in statistics view",
        deDE = "/gkeep loot stats         - Loot-Fenster in der Statistik-Ansicht öffnen",
    },
    CORE_HELP_LOOT_EXPORT = {
        enUS = "/gkeep loot export        - show an export string of the loot history (to copy)",
        deDE = "/gkeep loot export        - Export-String der Loot-Historie anzeigen (zum Kopieren)",
    },
    CORE_HELP_LOOT_IMPORT = {
        enUS = "/gkeep loot import        - open a paste window for a loot export string",
        deDE = "/gkeep loot import        - Einfüge-Fenster für einen Loot-Export-String öffnen",
    },
    CORE_HELP_EXPORT = {
        enUS = "/gkeep export             - data exchange: export string of the history for another Grindkeep user",
        deDE = "/gkeep export             - Datenaustausch: Verlauf als String für einen anderen Grindkeep-Nutzer",
    },
    CORE_HELP_IMPORT = {
        enUS = "/gkeep import             - open a paste window for an export string (recommended, no length limit)",
        deDE = "/gkeep import             - Einfüge-Fenster für einen Export-String öffnen (empfohlen, kein Längenlimit)",
    },
    CORE_HELP_RESET = {
        enUS = "/gkeep reset confirm      - delete all data for this guild",
        deDE = "/gkeep reset confirm      - alle Daten dieser Gilde löschen",
    },

    -- ============================================================
    -- Bestand / Mindestbestaende / Selbstdiagnose (seit v0.8)
    -- ============================================================
    CORE_HELP_STOCK = {
        enUS = "/gkeep stock [n|scan]     - current bank contents (top n), 'scan' re-reads them",
        deDE = "/gkeep stock [n|scan]     - aktueller Bankbestand (die größten n), 'scan' liest ihn neu ein",
    },
    CORE_HELP_MIN = {
        enUS = "/gkeep min <item> <count> - set a minimum stock (shift-click the item into chat), 0 removes it, 'list' shows all",
        deDE = "/gkeep min <Item> <Menge> - Mindestbestand festlegen (Item per Shift-Klick einfügen), 0 entfernt ihn, 'list' zeigt alle",
    },
    CORE_HELP_MISSING = {
        enUS = "/gkeep missing            - shopping list: what is below its minimum",
        deDE = "/gkeep missing            - Fehlliste: was unter dem Mindestbestand liegt",
    },
    CORE_HELP_CHECK = {
        enUS = "/gkeep check              - self-check: which bank functions this client offers and what they return",
        deDE = "/gkeep check              - Selbstdiagnose: welche Bank-Funktionen dieser Client kennt und was sie liefern",
    },

    CORE_STOCK_SCAN_START = { enUS = "Reading bank contents (%d tab(s)) ...", deDE = "Lese Bankbestand (%d Fach/Fächer) ..." },
    CORE_STOCK_SCAN_DONE = { enUS = "Bank contents read: %d different items.", deDE = "Bankbestand erfasst: %d verschiedene Gegenstände." },
    CORE_STOCK_UNRESOLVED = {
        enUS = "%d slots could not be identified yet (the client had not loaded those items) - they will be counted on the next scan.",
        deDE = "%d Plätze konnten noch nicht zugeordnet werden (der Client kannte diese Items noch nicht) - beim nächsten Scan sind sie dabei.",
    },
    CORE_STOCK_MISSING_HINT = {
        enUS = "%d item(s) are below their minimum - /gkeep missing shows the list.",
        deDE = "%d Eintrag/Einträge liegen unter dem Mindestbestand - /gkeep missing zeigt die Liste.",
    },
    CORE_STOCK_NO_DATA = {
        enUS = "No bank contents recorded yet - open the guild bank or use /gkeep stock scan.",
        deDE = "Noch kein Bankbestand erfasst - Gildenbank öffnen oder /gkeep stock scan nutzen.",
    },
    CORE_STOCK_EMPTY = { enUS = "The bank appears to be empty.", deDE = "Die Bank scheint leer zu sein." },
    CORE_STOCK_HEADER = { enUS = "Bank contents (%d different items):", deDE = "Bankbestand (%d verschiedene Gegenstände):" },
    CORE_STOCK_LINE = { enUS = "  %dx %s", deDE = "  %dx %s" },
    CORE_STOCK_MORE = { enUS = "  ... and %d more (raise the limit: /gkeep stock 50)", deDE = "  ... und %d weitere (mehr anzeigen: /gkeep stock 50)" },

    CORE_MIN_USAGE = {
        enUS = "Usage: /gkeep min <item link or item ID> <count> (0 removes it) | /gkeep min list",
        deDE = "Verwendung: /gkeep min <Itemlink oder Item-ID> <Menge> (0 entfernt ihn) | /gkeep min list",
    },
    CORE_MIN_SET = { enUS = "Minimum stock for %s set to %d.", deDE = "Mindestbestand für %s auf %d gesetzt." },
    CORE_MIN_REMOVED = { enUS = "Minimum stock for %s removed.", deDE = "Mindestbestand für %s entfernt." },
    CORE_MIN_NONE = {
        enUS = "No minimum stock levels set yet. Example: /gkeep min [item] 200",
        deDE = "Noch keine Mindestbestände hinterlegt. Beispiel: /gkeep min [Item] 200",
    },
    CORE_MIN_HEADER = { enUS = "Minimum stock levels:", deDE = "Mindestbestände:" },
    CORE_MIN_LINE = { enUS = "  %s - target %d, in bank %d", deDE = "  %s - Soll %d, in der Bank %d" },
    CORE_MISSING_NONE = { enUS = "Everything is at or above its minimum.", deDE = "Alles auf oder über dem Mindestbestand." },
    CORE_MISSING_HEADER = { enUS = "Missing:", deDE = "Es fehlt:" },
    CORE_MISSING_LINE = { enUS = "  %s - %d of %d, missing %d", deDE = "  %s - %d von %d, es fehlen %d" },

    CORE_CHECK_HEADER = { enUS = "Self-check:", deDE = "Selbstdiagnose:" },
    CORE_CHECK_FOOTER = {
        enUS = "If something looks wrong here, send this output along with your report.",
        deDE = "Falls hier etwas nicht stimmt: diese Ausgabe einfach mitschicken.",
    },
    CORE_CHECK_GUILD = { enUS = "Guild", deDE = "Gilde" },
    CORE_CHECK_NO_GUILD = { enUS = "not in a guild", deDE = "in keiner Gilde" },
    CORE_CHECK_APIS = { enUS = "Bank functions", deDE = "Bank-Funktionen" },
    CORE_CHECK_ALL_PRESENT = { enUS = "all present", deDE = "alle vorhanden" },
    CORE_CHECK_MISSING = { enUS = "MISSING:", deDE = "FEHLEN:" },
    CORE_CHECK_TABS = { enUS = "Tabs reported", deDE = "Gemeldete Fächer" },
    CORE_CHECK_TAB_LABEL = { enUS = "Tab %d", deDE = "Fach %d" },
    CORE_CHECK_VIEWABLE = { enUS = "viewable", deDE = "einsehbar" },
    CORE_CHECK_FIRST_LOG = { enUS = "first log entry", deDE = "erster Log-Eintrag" },
    CORE_CHECK_STOCK = { enUS = "Bank contents", deDE = "Bankbestand" },
    CORE_CHECK_STOCK_VALUE = { enUS = "%d items, read %s", deDE = "%d Gegenstände, gelesen %s" },
    CORE_CHECK_TX = { enUS = "Stored transactions", deDE = "Gespeicherte Transaktionen" },

    -- ============================================================
    -- Stock.lua - Bestandsfenster
    -- ============================================================
    STOCK_WINDOW_TITLE = { enUS = "Grindkeep - Stock", deDE = "Grindkeep - Bestand" },
    STOCK_BUTTON = { enUS = "Stock", deDE = "Bestand" },
    STOCK_FILTER_ALL = { enUS = "Showing: everything", deDE = "Anzeige: alles" },
    STOCK_FILTER_MISSING = { enUS = "Showing: missing only", deDE = "Anzeige: nur Fehlendes" },
    STOCK_RESCAN_BUTTON = { enUS = "Re-read", deDE = "Neu einlesen" },
    STOCK_HINT = {
        enUS = "Set a minimum with /gkeep min <item> <count> - shift-click an item into the chat line to insert it.",
        deDE = "Mindestbestand setzen mit /gkeep min <Item> <Menge> - das Item per Shift-Klick in die Chatzeile einfügen.",
    },
    STOCK_SCANNED_AT = { enUS = "read %s", deDE = "gelesen %s" },
    STOCK_NEVER_SCANNED = { enUS = "not read yet", deDE = "noch nicht gelesen" },
    STOCK_ROW_MISSING = { enUS = "target %d - missing %d", deDE = "Soll %d - es fehlen %d" },
    STOCK_ROW_OK = { enUS = "target %d - covered", deDE = "Soll %d - gedeckt" },
    STOCK_ROW_NO_MINIMUM = { enUS = "no minimum set", deDE = "kein Mindestbestand hinterlegt" },
    STOCK_EMPTY = {
        enUS = "Nothing recorded yet - open the guild bank, press \"Re-read\" or set up a storage alt.",
        deDE = "Noch nichts erfasst - Gildenbank öffnen, \"Neu einlesen\" drücken oder einen Lager-Twink anmelden.",
    },
    STOCK_EMPTY_MISSING = { enUS = "Nothing is missing.", deDE = "Es fehlt nichts." },

    -- ============================================================
    -- Minimap-Knopf und Reiter im Gildenbank-Fenster
    -- ============================================================
    MINIMAP_TOOLTIP_TITLE = { enUS = "Grindkeep", deDE = "Grindkeep" },
    MINIMAP_TOOLTIP_LEFT = { enUS = "Left click: open the window", deDE = "Linksklick: Fenster öffnen" },
    MINIMAP_TOOLTIP_RIGHT = { enUS = "Right click: stock window", deDE = "Rechtsklick: Bestandsfenster" },
    MINIMAP_TOOLTIP_DRAG = { enUS = "Drag to move around the minimap", deDE = "Ziehen verschiebt den Knopf um die Minimap" },
    BANK_TAB_LABEL = { enUS = "Grindkeep", deDE = "Grindkeep" },

    -- ============================================================
    -- Help.lua - Erklaerung im Spiel
    -- ============================================================
    HELP_TITLE = { enUS = "Grindkeep - What this does", deDE = "Grindkeep - Was das hier macht" },
    HELP_BUTTON_TOOLTIP = { enUS = "What does this addon do?", deDE = "Was macht dieses Addon?" },
    HELP_H_WHAT = { enUS = "In short", deDE = "Kurz gesagt" },
    HELP_T_WHAT = {
        enUS = "Grindkeep answers two questions about your guild bank: who puts things in and takes things out, and what is actually in there right now. It runs by itself - just open the guild bank now and then, everything else happens automatically.",
        deDE = "Grindkeep beantwortet zwei Fragen zur Gildenbank: wer legt etwas hinein und nimmt etwas heraus, und was liegt gerade tatsächlich drin. Es läuft von allein - öffne einfach ab und zu die Gildenbank, alles Weitere passiert automatisch.",
    },
    HELP_H_WINDOWS = { enUS = "The tabs", deDE = "Die Reiter" },
    HELP_T_WINDOWS = {
        enUS = "Open the window with /gkeep, the minimap button or the Grindkeep tab in the guild bank. At the top you pick the period (all, 7, 30 or 90 days) - it applies to Overview, Members and Transactions.\n\nOverview: gold deposited and withdrawn, the balance, items in and out, the latest transactions and the players with the highest balance.\n\nMembers: every player with their balance (deposited minus withdrawn). Click a name for details and transactions (alts included), right-click for more options.\n\nTransactions: search by player, item or tab - e.g. who took the flasks.\n\nStock: what is currently in the tabs, with minimum amounts.\n\nLoot (only when switched on in the options): who received which item in raids.",
        deDE = "Das Fenster öffnest du mit /gkeep, dem Minimap-Knopf oder dem Grindkeep-Reiter in der Gildenbank. Oben wählst du den Zeitraum (alles, 7, 30 oder 90 Tage) - er gilt für Übersicht, Mitglieder und Vorgänge.\n\nÜbersicht: eingezahltes und entnommenes Gold, die Bilanz, Gegenstände rein und raus, die letzten Vorgänge und die Spieler mit der höchsten Bilanz.\n\nMitglieder: alle Spieler mit ihrer Bilanz (eingezahlt minus entnommen). Klick auf einen Namen zeigt Details und Vorgänge (samt Twinks), Rechtsklick weitere Möglichkeiten.\n\nVorgänge: Suche nach Spieler, Gegenstand oder Fach - z.B. wer die Fläschchen genommen hat.\n\nBestand: was gerade in den Fächern liegt, mit Mindestmengen.\n\nLoot (nur wenn in den Optionen eingeschaltet): wer in Schlachtzügen welchen Gegenstand bekommen hat.",
    },
    HELP_H_STOCK = { enUS = "Minimum stock levels", deDE = "Mindestbestände" },
    HELP_T_STOCK = {
        enUS = "Decide how much of something should always be available (guild bank and storage alts together):\n\n  /gkeep min [item] 200\n\nShift-click the item in your bags to paste it into the chat line. From then on Grindkeep reports when it drops below that, and /gkeep missing gives you the shopping list. 0 removes an entry again.",
        deDE = "Lege fest, wie viel von etwas immer vorrätig sein soll (Gildenbank und Lager-Twinks zusammen):\n\n  /gkeep min [Item] 200\n\nDen Gegenstand mit Shift-Klick aus den Taschen in die Chatzeile einfügen. Ab dann meldet Grindkeep, wenn der Bestand darunter fällt, und /gkeep missing zeigt dir die Einkaufsliste. Mit 0 entfernst du einen Eintrag wieder.",
    },
    HELP_H_LOOT = { enUS = "Loot", deDE = "Loot" },
    HELP_T_LOOT = {
        enUS = "Loot tracking is off by default. Once switched on in the options, Grindkeep records who received which item in raids (from rare quality upwards, both adjustable). Useful when someone asks whether a player already received a certain item: /gkeep loot check <item>.",
        deDE = "Die Loot-Erfassung ist standardmäßig aus. Eingeschaltet in den Optionen schreibt Grindkeep mit, wer in Schlachtzügen welchen Gegenstand bekommen hat (ab seltener Qualität, beides einstellbar). Nützlich, wenn jemand fragt, ob ein Spieler einen bestimmten Gegenstand schon bekommen hat: /gkeep loot check <Item>.",
    },
    HELP_H_ALTS = { enUS = "Alts", deDE = "Twinks" },
    HELP_T_ALTS = {
        enUS = "So that an alt counts towards its main character, assign it once - right-click the name in the main window, or:\n\n  /gkeep alt <alt> = <main>\n\nTo undo it: /gkeep unalt <alt>. If your guild rank is high enough, both are shared with other guild members who use Grindkeep.",
        deDE = "Damit ein Twink seinem Hauptcharakter zugerechnet wird, ordne ihn einmal zu - per Rechtsklick auf den Namen im Hauptfenster oder mit:\n\n  /gkeep alt <Twink> = <Main>\n\nRückgängig machen: /gkeep unalt <Twink>. Ist dein Gildenrang hoch genug, wird beides an andere Gildenmitglieder mit Grindkeep weitergegeben.",
    },
    HELP_H_LIMITS = { enUS = "What it cannot do", deDE = "Was es nicht kann" },
    HELP_T_LIMITS = {
        enUS = "WoW only shows the last 25 entries per tab in the bank log, and nothing from before the addon was installed. So the history has gaps if nobody opens the bank for a while - the more often someone with Grindkeep looks in, the more complete it gets. The stock, on the other hand, is always complete.\n\nEntries older than one year are removed automatically so the saved data does not grow forever (adjustable in the options).",
        deDE = "WoW zeigt im Bank-Log nur die letzten 25 Einträge pro Fach, und nichts von vor der Installation. Die Historie hat also Lücken, wenn längere Zeit niemand die Bank öffnet - je öfter jemand mit Grindkeep hineinschaut, desto lückenloser wird sie. Der Bestand ist dagegen immer vollständig.\n\nEinträge, die älter als ein Jahr sind, werden automatisch entfernt, damit die gespeicherten Daten nicht endlos wachsen (einstellbar in den Optionen).",
    },
    HELP_H_COMMANDS = { enUS = "Commands", deDE = "Befehle" },
    HELP_T_COMMANDS = {
        enUS = "/gkeep - open the window\n/gkeep stock - bank contents\n/gkeep missing - what is missing\n/gkeep min [item] <count> - set a minimum\n/gkeep list - all players\n/gkeep player <name> - details\n/gkeep style ... - font, size, opacity\n/gkeep check - self-check when something looks wrong\n/gkeep options - settings\n\nA full list is printed by /gkeep followed by an unknown word, e.g. /gkeep ?",
        deDE = "/gkeep - Fenster öffnen\n/gkeep stock - Bankbestand\n/gkeep missing - was fehlt\n/gkeep min [Item] <Menge> - Mindestbestand setzen\n/gkeep list - alle Spieler\n/gkeep player <Name> - Details\n/gkeep style ... - Schriftart, Größe, Deckkraft\n/gkeep check - Selbstdiagnose, wenn etwas nicht stimmt\n/gkeep options - Einstellungen\n\nDie vollständige Liste erscheint mit /gkeep und einem unbekannten Wort, z.B. /gkeep ?",
    },

    -- ============================================================
    -- Style.lua - Schrift und Aussehen
    -- ============================================================
    STYLE_FONT_DEFAULT = { enUS = "Default", deDE = "Standard" },
    STYLE_FONT_ARIAL = { enUS = "Arial Narrow", deDE = "Arial Narrow" },
    STYLE_FONT_FRIZ = { enUS = "Friz Quadrata", deDE = "Friz Quadrata" },
    STYLE_FONT_MORPHEUS = { enUS = "Morpheus", deDE = "Morpheus" },
    STYLE_FONT_SKURRI = { enUS = "Skurri", deDE = "Skurri" },
    STYLE_FONT_SET = { enUS = "Font set to %s.", deDE = "Schriftart auf %s gesetzt." },
    STYLE_FONT_UNKNOWN = { enUS = "Unknown font. Available: %s", deDE = "Unbekannte Schriftart. Möglich sind: %s" },
    STYLE_SIZE_SET = { enUS = "Font size set to %d%%.", deDE = "Schriftgröße auf %d%% gesetzt." },
    STYLE_OPACITY_SET = { enUS = "Window opacity set to %d%%.", deDE = "Fenster-Deckkraft auf %d%% gesetzt." },
    STYLE_USAGE = {
        enUS = "Usage: /gkeep style font <name> | /gkeep style size <70-160> | /gkeep style opacity <30-100>",
        deDE = "Verwendung: /gkeep style font <Name> | /gkeep style size <70-160> | /gkeep style opacity <30-100>",
    },
    CORE_HELP_HELPWINDOW = {
        enUS = "/gkeep help               - what this addon does, explained in game",
        deDE = "/gkeep help               - was dieses Addon macht, im Spiel erklärt",
    },
    CORE_HELP_STYLE = {
        enUS = "/gkeep style ...          - font, font size and window opacity",
        deDE = "/gkeep style ...          - Schriftart, Schriftgröße und Fenster-Deckkraft",
    },
    OPT_SECTION_STYLE = { enUS = "Appearance", deDE = "Aussehen" },
    OPT_FONT_LABEL = { enUS = "Font", deDE = "Schriftart" },
    OPT_FONT_TOOLTIP = {
        enUS = "Font used in all Grindkeep windows. Only fonts that WoW itself ships with.",
        deDE = "Schriftart in allen Grindkeep-Fenstern. Nur Schriften, die WoW selbst mitbringt.",
    },
    OPT_FONTSIZE_LABEL = { enUS = "Font size", deDE = "Schriftgröße" },
    OPT_FONTSIZE_TOOLTIP = {
        enUS = "Scales all text. 100% is the original size; headings stay larger than sub-text.",
        deDE = "Skaliert alle Texte. 100% ist die Originalgröße; Überschriften bleiben größer als Unterzeilen.",
    },
    OPT_OPACITY_LABEL = { enUS = "Window opacity", deDE = "Fenster-Deckkraft" },
    OPT_OPACITY_TOOLTIP = {
        enUS = "How opaque the Grindkeep windows are. Lower values also dim the text.",
        deDE = "Wie undurchsichtig die Grindkeep-Fenster sind. Niedrigere Werte blassen auch den Text ab.",
    },

    -- Options.lua - neue Einstellungen
    OPT_AUTOSTOCK_LABEL = { enUS = "Also read bank contents", deDE = "Auch den Bankbestand einlesen" },
    OPT_AUTOSTOCK_TOOLTIP = {
        enUS = "After reading the log, also record what is currently in the tabs. This is what the stock window and the minimum stock levels are based on.",
        deDE = "Liest nach dem Log zusätzlich ein, was gerade in den Fächern liegt. Darauf beruhen das Bestandsfenster und die Mindestbestände.",
    },
    OPT_SECTION_ACCESS = { enUS = "Access", deDE = "Bedienung" },
    OPT_MINIMAP_LABEL = { enUS = "Minimap button", deDE = "Minimap-Knopf" },
    OPT_MINIMAP_TOOLTIP = {
        enUS = "Shows a button next to the minimap. Left click opens the main window, right click the stock window.",
        deDE = "Zeigt einen Knopf neben der Minimap. Linksklick öffnet das Hauptfenster, Rechtsklick das Bestandsfenster.",
    },
    OPT_BANKTAB_LABEL = { enUS = "Tab in the guild bank window", deDE = "Reiter im Gildenbank-Fenster" },
    OPT_BANKTAB_TOOLTIP = {
        enUS = "Adds a Grindkeep tab next to \"Info\" in the guild bank window.",
        deDE = "Setzt im Gildenbank-Fenster einen Grindkeep-Reiter neben \"Info\".",
    },
    CORE_OPTIONS_UNAVAILABLE = {
        enUS = "Options window unavailable. You can also find it under Options -> AddOns -> Grindkeep.",
        deDE = "Optionsfenster nicht verfügbar. Du findest es auch unter Optionen -> AddOns -> Grindkeep.",
    },
    CORE_ALT_ASSIGNED = { enUS = "%s is now registered as an alt of %s.", deDE = "%s ist jetzt als Twink von %s eingetragen." },
    CORE_INVALID_INPUT = { enUS = "Invalid input.", deDE = "Ungültige Eingabe." },
    LOOT_MODULE_NOT_LOADED = { enUS = "Loot module not loaded.", deDE = "Loot-Modul nicht geladen." },
    CORE_RESET_DONE = { enUS = "This guild's data has been deleted.", deDE = "Daten dieser Gilde wurden gelöscht." },
    CORE_RESET_CONFIRM = {
        enUS = "Warning: this deletes ALL data for this guild. To confirm: /gkeep reset confirm",
        deDE = "Achtung: löscht ALLE Daten dieser Gilde. Zum Bestätigen: /gkeep reset confirm",
    },

    -- ============================================================
    -- Comm.lua
    -- ============================================================
    COMM_ALT_RECEIVED = {
        enUS = "Alt assignment received from %s: %s -> %s",
        deDE = "Twink-Zuordnung von %s übernommen: %s -> %s",
    },
    COMM_ALT_SYNC_RECEIVED = {
        enUS = "%d alt assignment(s) received from %s (login sync).",
        deDE = "%d Twink-Zuordnung(en) von %s übernommen (Login-Abgleich).",
    },
    COMM_EXPORT_TITLE = {
        enUS = "Export string (selected, copy with Ctrl+C):",
        deDE = "Export-String (markiert, mit Strg+C kopieren):",
    },
    COMM_IMPORT_TITLE = {
        enUS = "Paste export string (Ctrl+V) and confirm:",
        deDE = "Export-String einfügen (Strg+V) und bestätigen:",
    },
    COMM_IMPORT_BUTTON = { enUS = "Import", deDE = "Importieren" },
    COMM_EXPORT_NONE = { enUS = "No transactions available to export.", deDE = "Keine Transaktionen zum Exportieren vorhanden." },
    COMM_IMPORT_NEED_STRING = {
        enUS = "Please provide an export string: /gkeep import (opens a paste window) or /gkeep import <short string>",
        deDE = "Bitte einen Export-String angeben: /gkeep import (öffnet ein Einfüge-Fenster) oder /gkeep import <kurzer String>",
    },
    COMM_IMPORT_INVALID = { enUS = "Invalid import string.", deDE = "Ungültiger Import-String." },
    COMM_IMPORT_EMPTY = { enUS = "No transactions found in the import string.", deDE = "Keine Transaktionen im Import-String gefunden." },
    COMM_IMPORT_DONE = {
        enUS = "Import complete: %d of %d entries newly added (the rest were already known).",
        deDE = "Import abgeschlossen: %d von %d Einträgen neu übernommen (Rest war bereits bekannt).",
    },
    COMM_LOOT_EXPORT_TITLE = {
        enUS = "Loot history export string (selected, copy with Ctrl+C):",
        deDE = "Export-String der Loot-Historie (markiert, mit Strg+C kopieren):",
    },
    COMM_LOOT_IMPORT_TITLE = {
        enUS = "Paste loot history export string (Ctrl+V) and confirm:",
        deDE = "Export-String der Loot-Historie einfügen (Strg+V) und bestätigen:",
    },
    COMM_LOOT_EXPORT_NONE = { enUS = "No loot entries available to export.", deDE = "Keine Loot-Einträge zum Exportieren vorhanden." },
    COMM_LOOT_IMPORT_NEED_STRING = {
        enUS = "Please provide an export string: /gkeep loot import (opens a paste window) or /gkeep loot import <short string>",
        deDE = "Bitte einen Export-String angeben: /gkeep loot import (öffnet ein Einfüge-Fenster) oder /gkeep loot import <kurzer String>",
    },
    COMM_LOOT_IMPORT_EMPTY = { enUS = "No loot entries found in the import string.", deDE = "Keine Loot-Einträge im Import-String gefunden." },
    COMM_LOOT_IMPORT_DONE = {
        enUS = "Loot import complete: %d of %d entries newly added (the rest were already known).",
        deDE = "Loot-Import abgeschlossen: %d von %d Einträgen neu übernommen (Rest war bereits bekannt).",
    },

    -- ============================================================
    -- Options.lua
    -- ============================================================
    OPT_SECTION_SCAN = { enUS = "Scanning", deDE = "Scannen" },
    OPT_AUTOSCAN_LABEL = { enUS = "Scan automatically", deDE = "Automatisch scannen" },
    OPT_AUTOSCAN_TOOLTIP = {
        enUS = "Automatically starts a scan as soon as you open the guild bank window. When disabled, you can still start one manually anytime with /gkeep scan.",
        deDE = "Startet automatisch einen Scan, sobald du das Gildenbank-Fenster öffnest. Ausgeschaltet kannst du weiterhin jederzeit manuell mit /gkeep scan starten.",
    },
    OPT_SCAN_CHAT_LABEL = { enUS = "Scan messages in chat", deDE = "Scan-Meldungen im Chat" },
    OPT_SCAN_CHAT_TOOLTIP = {
        enUS = "Shows 'scan started' and 'scan complete' in chat. Error messages (e.g. no guild) always appear regardless.",
        deDE = "Zeigt 'Scan gestartet' und 'Scan abgeschlossen' im Chat an. Fehlermeldungen (z.B. keine Gilde) erscheinen unabhängig davon immer.",
    },
    OPT_SECTION_TWINKSYNC = { enUS = "Sync Alt Assignments With the Guild", deDE = "Twink-Zuordnung mit der Gilde abgleichen" },
    OPT_SYNC_ENABLED_LABEL = { enUS = "Sync automatically", deDE = "Automatisch synchronisieren" },
    OPT_SYNC_ENABLED_TOOLTIP = {
        enUS = "Automatically syncs alt/main assignments with other online members who also have Grindkeep installed. When disabled, this client no longer sends or accepts assignments automatically - manual export/import (/gkeep export or /gkeep import) still works.",
        deDE = "Gleicht Twink-/Hauptcharakter-Zuordnungen automatisch mit anderen Online-Mitgliedern ab, die Grindkeep ebenfalls installiert haben. Ausgeschaltet sendet und übernimmt dieser Client keine Zuordnungen mehr automatisch - der manuelle Export/Import (/gkeep export bzw. /gkeep import) funktioniert trotzdem weiter.",
    },
    OPT_TRUST_RANK_LABEL = { enUS = "Trust Threshold (Guild Rank)", deDE = "Vertrauensgrenze (Gildenrang)" },
    OPT_TRUST_RANK_TOOLTIP = {
        enUS = "Only members up to this guild rank may automatically distribute alt assignments to the guild, or have them accepted automatically. 0 is the highest rank (e.g. Guild Master), higher numbers are lower ranks.",
        deDE = "Nur Mitglieder bis zu diesem Gildenrang dürfen Twink-Zuordnungen automatisch an die Gilde verteilen bzw. werden dabei automatisch übernommen. 0 ist der höchste Rang (z.B. Gildenmeister), höhere Zahlen sind niedrigere Ränge.",
    },
    OPT_RANK_FORMAT = { enUS = "Rank %d", deDE = "Rang %d" },
    OPT_SECTION_LOOT = { enUS = "Loot Tracking", deDE = "Loot-Tracking" },
    OPT_LOOT_ENABLED_LABEL = {
        enUS = "Record raid loot",
        deDE = "Raid-Loot erfassen",
    },
    OPT_LOOT_ENABLED_TOOLTIP = {
        enUS = "Records who received which item (from the loot message in chat, regardless of loot method). Off by default. View it with /gkeep loot check <item> or the Loot button in the main window.",
        deDE = "Schreibt mit, wer welchen Gegenstand bekommen hat (über den Loot-Hinweis im Chat, unabhängig vom Beute-Modus). Standardmäßig aus. Abrufbar per /gkeep loot check <Item> oder über den Loot-Knopf im Hauptfenster.",
    },
    OPT_LOOT_SYNC_LABEL = { enUS = "Sync loot with the guild", deDE = "Loot mit der Gilde abgleichen" },
    OPT_LOOT_SYNC_TOOLTIP = {
        enUS = "Automatically syncs recorded loot entries with other online members who also have Grindkeep installed (uses the same trust threshold as the alt sync above). When disabled, this client still records loot locally, but no longer sends or accepts anything automatically.",
        deDE = "Gleicht erfasste Loot-Einträge automatisch mit anderen Online-Mitgliedern ab, die Grindkeep ebenfalls installiert haben (nutzt dieselbe Vertrauensgrenze wie der Twink-Abgleich oben). Ausgeschaltet erfasst dieser Client Loot weiterhin lokal, sendet und übernimmt aber nichts mehr automatisch.",
    },
    OPT_LOOT_MINQ_LABEL = { enUS = "Minimum Quality", deDE = "Mindest-Qualität" },
    OPT_LOOT_MINQ_TOOLTIP = {
        enUS = "Items below this quality are not recorded as loot. Default: Rare (blue).",
        deDE = "Gegenstände unterhalb dieser Qualität werden nicht als Loot erfasst. Standard: Selten (blau).",
    },
    OPT_QUALITY_0 = { enUS = "Poor", deDE = "Schlecht" },
    OPT_QUALITY_1 = { enUS = "Common", deDE = "Gewöhnlich" },
    OPT_QUALITY_2 = { enUS = "Uncommon", deDE = "Ungewöhnlich" },
    OPT_QUALITY_3 = { enUS = "Rare", deDE = "Selten" },
    OPT_QUALITY_4 = { enUS = "Epic", deDE = "Episch" },
    OPT_QUALITY_5 = { enUS = "Legendary", deDE = "Legendär" },

    -- ============================================================
    -- UI.lua
    -- ============================================================
    UI_RELATIVE_JUSTNOW = { enUS = "just now", deDE = "gerade eben" },
    UI_RELATIVE_MIN = { enUS = " min", deDE = " Min." },
    UI_RELATIVE_HOUR = { enUS = " h", deDE = " Std." },
    UI_RELATIVE_DAY = { enUS = " d", deDE = " Tg." },
    UI_CTX_WHISPER = { enUS = "Whisper", deDE = "Flüstern" },
    UI_CTX_INVITE = { enUS = "Invite to Group", deDE = "In Gruppe einladen" },
    UI_CTX_INVITE_FAILED = { enUS = "Invite failed (API may differ).", deDE = "Einladen fehlgeschlagen (API evtl. abweichend)." },
    UI_CTX_REPORT = { enUS = "Post Report", deDE = "Bericht posten" },
    UI_CTX_REPORT_GUILD = { enUS = "To Guild Chat", deDE = "In Gildenchat" },
    UI_CTX_REPORT_OFFICER = { enUS = "To Officer Chat", deDE = "In Offizierschat" },
    UI_CTX_ASSIGN_TWINK = { enUS = "Assign as Alt ...", deDE = "Als Twink zuweisen ..." },
    UI_REPORT_LINE = {
        enUS = "%s: Net %s%s (Items in %d / out %d)",
        deDE = "%s: Netto %s%s (Items ein %d / aus %d)",
    },
    UI_REPORT_SEND_FAILED = {
        enUS = "Message could not be sent (channel may be unavailable, e.g. no officer permissions).",
        deDE = "Nachricht konnte nicht gesendet werden (Kanal evtl. nicht verfügbar, z.B. keine Offiziersrechte).",
    },
    UI_ASSIGN_TWINK_POPUP_TEXT = { enUS = "%s is an alt of:", deDE = "%s ist Twink von:" },
    UI_TWINK_ASSIGNED = { enUS = "%s was assigned as an alt of %s.", deDE = "%s wurde %s als Twink zugewiesen." },
    UI_SORT_NET = { enUS = "Balance", deDE = "Bilanz" },
    UI_SORT_ACTIVITY = { enUS = "Activity", deDE = "Aktivität" },
    UI_SORT_NAME = { enUS = "Name", deDE = "Name" },
    UI_NO_DATA = {
        enUS = "(no data - open the guild bank or /gkeep scan)",
        deDE = "(keine Daten - Gildenbank öffnen oder /gkeep scan)",
    },
    UI_TOTAL_LABEL = { enUS = "Total:", deDE = "Gesamt:" },
    UI_TAB_ALL = { enUS = "All", deDE = "Alle" },
    UI_TAB_GOLD = { enUS = "Gold", deDE = "Gold" },
    UI_TAB_ITEMS = { enUS = "Items", deDE = "Gegenstände" },
    UI_SELECT_PLAYER = { enUS = "Select a player on the left to see their deposits and withdrawals.", deDE = "Wähle links einen Spieler aus, um seine Einzahlungen und Entnahmen zu sehen." },
    UI_TWINK_OF_SUFFIX = { enUS = "(alt of %s)", deDE = "(Twink von %s)" },
    UI_GOLD_LOG_LABEL = { enUS = "Gold Log", deDE = "Gold-Log" },
    UI_TAB_LABEL = { enUS = "Tab %s", deDE = "Tab %s" },
    -- Wortstellung unterscheidet sich bewusst (Deutsch: Praefix "vor",
    -- Englisch: Suffix "ago") - deshalb eigener Platzhalter-String statt
    -- fester Konkatenation im Aufrufer.
    UI_TIME_AGO = { enUS = "%s ago", deDE = "vor %s" },

    -- ============================================================
    -- Loot.lua
    -- ============================================================
    LOOT_PARSE_ERROR = {
        enUS = "Error while parsing a loot message: %s",
        deDE = "Fehler beim Auswerten einer Loot-Nachricht: %s",
    },
    LOOT_RECORDED_CHAT = { enUS = "Loot recorded: %s -> %s%s", deDE = "Loot erfasst: %s -> %s%s" },
    LOOT_NEED_ITEM = { enUS = "Please provide an item: /gkeep loot check <Name>", deDE = "Bitte Item angeben: /gkeep loot check <Name>" },
    LOOT_NONE_FOUND = { enUS = "No loot entries found for: %s", deDE = "Keine Loot-Einträge gefunden für: %s" },
    LOOT_FOUND_COUNT = { enUS = "%d entries found:", deDE = "%d Eintrag/Einträge gefunden:" },
    LOOT_NONE_RECORDED = {
        enUS = "No loot recorded yet (group/raid loot triggers recording automatically).",
        deDE = "Noch kein Loot erfasst (Gruppen-/Raid-Loot löst die Erfassung automatisch aus).",
    },
    LOOT_HELP = {
        enUS = "Commands: /gkeep loot check <Item> | /gkeep loot recent [n] | /gkeep loot ui | /gkeep loot stats | /gkeep loot export | /gkeep loot import",
        deDE = "Befehle: /gkeep loot check <Item> | /gkeep loot recent [n] | /gkeep loot ui | /gkeep loot stats | /gkeep loot export | /gkeep loot import",
    },
    LOOT_WINDOW_TITLE = { enUS = "Grindkeep - Loot", deDE = "Grindkeep - Loot" },
    LOOT_SEARCH_HINT = {
        enUS = "Enter an item or player name - leave empty to show recent entries",
        deDE = "Item- oder Spielername eingeben - leer zeigt die letzten Einträge",
    },
    LOOT_DISABLED_HINT = {
        enUS = "Automatic loot recording is disabled (see Options -> AddOns -> Grindkeep).",
        deDE = "Automatische Loot-Erfassung ist deaktiviert (siehe Optionen -> AddOns -> Grindkeep).",
    },
    LOOT_UNKNOWN_ITEM = { enUS = "? (unknown item)", deDE = "? (unbekanntes Item)" },
    LOOT_VIA_SUFFIX = { enUS = " (via %s)", deDE = " (via %s)" },
    LOOT_MODE_STATS_BUTTON = { enUS = "Stats", deDE = "Statistik" },
    LOOT_MODE_SEARCH_BUTTON = { enUS = "Search", deDE = "Suche" },
    LOOT_STATS_SORT_COUNT = { enUS = "Amount", deDE = "Anzahl" },
    LOOT_STATS_SORT_ENTRIES = { enUS = "Events", deDE = "Ereignisse" },
    LOOT_STATS_SORT_RECENT = { enUS = "Recent", deDE = "Zuletzt" },
    LOOT_STATS_ROW_MAIN = { enUS = "%s: %d items", deDE = "%s: %d Items" },
    LOOT_STATS_ROW_SUB = { enUS = "%d loot events - last: %s", deDE = "%d Loot-Ereignisse - zuletzt: %s" },
    CORE_BANK_NOT_OPEN = {
        enUS = "Open the guild bank first - without it, the server sends no data.",
        deDE = "Öffne zuerst die Gildenbank - ohne sie schickt der Server keine Daten.",
    },
    CORE_PRUNED = {
        enUS = "%d entries older than the retention period were removed.",
        deDE = "%d Einträge, älter als die Aufbewahrungsdauer, wurden entfernt.",
    },
    CORE_ALT_USAGE = {
        enUS = "Usage: /gkeep alt <alt> = <main>  (the two characters must differ and must not already be linked the other way round)",
        deDE = "Verwendung: /gkeep alt <Twink> = <Main>  (zwei verschiedene Charaktere, die nicht schon umgekehrt verknüpft sind)",
    },
    CORE_ALT_CLEARED = {
        enUS = "%s is no longer assigned as an alt.",
        deDE = "%s ist nicht mehr als Twink zugeordnet.",
    },
    CORE_ALT_NOT_FOUND = {
        enUS = "No alt assignment found for \"%s\".",
        deDE = "Keine Twink-Zuordnung für \"%s\" gefunden.",
    },
    CORE_HELP_UNALT = {
        enUS = "/gkeep unalt <alt>        - remove an alt assignment",
        deDE = "/gkeep unalt <Twink>      - Twink-Zuordnung aufheben",
    },
    CORE_HELP_SEARCH = {
        enUS = "/gkeep search [text]      - search all transactions",
        deDE = "/gkeep search [Text]      - alle Vorgänge durchsuchen",
    },
    DATE_FORMAT = {
        enUS = "%m/%d/%Y %H:%M",
        deDE = "%d.%m.%Y %H:%M",
    },
    DATE_FORMAT_SHORT = {
        enUS = "%m/%d %H:%M",
        deDE = "%d.%m. %H:%M",
    },
    DATE_FORMAT_DAY = {
        enUS = "%m/%d/%Y",
        deDE = "%d.%m.%Y",
    },
    COMM_ALT_REMOVED_RECEIVED = {
        enUS = "%s removed the alt assignment of %s.",
        deDE = "%s hat die Twink-Zuordnung von %s aufgehoben.",
    },
    COMM_IMPORT_SKIPPED = {
        enUS = "%d invalid entries were skipped.",
        deDE = "%d ungültige Einträge wurden übersprungen.",
    },
    UI_CTX_UNASSIGN_TWINK = {
        enUS = "Remove alt assignment",
        deDE = "Twink-Zuordnung aufheben",
    },
    UI_CTX_SEARCH_PLAYER = {
        enUS = "Show all transactions",
        deDE = "Alle Vorgänge anzeigen",
    },
    UI_PERIOD_ALL = {
        enUS = "All",
        deDE = "Alles",
    },
    UI_PERIOD_7 = {
        enUS = "7 days",
        deDE = "7 Tage",
    },
    UI_PERIOD_30 = {
        enUS = "30 days",
        deDE = "30 Tage",
    },
    UI_PERIOD_90 = {
        enUS = "90 days",
        deDE = "90 Tage",
    },
    UI_PERIOD_TOOLTIP = {
        enUS = "Only count transactions from this period.",
        deDE = "Nur Vorgänge aus diesem Zeitraum zählen.",
    },
    UI_TOTAL_LABEL_PERIOD = {
        enUS = "Net, last %d days:",
        deDE = "Netto, letzte %d Tage:",
    },
    SEARCH_BUTTON = {
        enUS = "Search",
        deDE = "Suche",
    },
    SEARCH_WINDOW_TITLE = {
        enUS = "Search transactions",
        deDE = "Vorgänge durchsuchen",
    },
    SEARCH_HINT = {
        enUS = "Player, item or tab - or shift-click an item",
        deDE = "Spieler, Gegenstand oder Fach - oder Shift-Klick auf ein Item",
    },
    SEARCH_MODE_ALL = {
        enUS = "All",
        deDE = "Alle",
    },
    SEARCH_MODE_DEPOSIT = {
        enUS = "Deposits",
        deDE = "Einzahlungen",
    },
    SEARCH_MODE_WITHDRAW = {
        enUS = "Withdrawals",
        deDE = "Entnahmen",
    },
    SEARCH_MODE_GOLD = {
        enUS = "Gold",
        deDE = "Gold",
    },
    SEARCH_MODE_ITEM = {
        enUS = "Items",
        deDE = "Gegenstände",
    },
    SEARCH_ACTION_DEPOSIT = {
        enUS = "deposited",
        deDE = "legte ein",
    },
    SEARCH_ACTION_WITHDRAW = {
        enUS = "took",
        deDE = "nahm",
    },
    SEARCH_ACTION_MOVE = {
        enUS = "moved",
        deDE = "verschob",
    },
    SEARCH_ACTION_REPAIR = {
        enUS = "repaired for",
        deDE = "reparierte für",
    },
    SEARCH_PLAYER_FILTER = {
        enUS = "Player: %s (incl. alts)",
        deDE = "Spieler: %s (inkl. Twinks)",
    },
    SEARCH_NO_RESULTS = {
        enUS = "No matching transactions.",
        deDE = "Keine passenden Vorgänge.",
    },
    SEARCH_SUMMARY = {
        enUS = "%d results  -  items in %d / out %d  -  gold in %s / out %s",
        deDE = "%d Treffer  -  Gegenstände rein %d / raus %d  -  Gold rein %s / raus %s",
    },
    SEARCH_LIMIT_HINT = {
        enUS = "(showing the newest 500)",
        deDE = "(die neuesten 500 werden angezeigt)",
    },
    OPT_SECTION_DATA = {
        enUS = "Saved data",
        deDE = "Gespeicherte Daten",
    },
    OPT_RETENTION_LABEL = {
        enUS = "Keep entries for",
        deDE = "Einträge aufbewahren",
    },
    OPT_RETENTION_TOOLTIP = {
        enUS = "Transactions and loot older than this are removed at login, so the saved data does not grow forever. Stock and minimum amounts are not affected. \"Forever\" keeps everything.",
        deDE = "Vorgänge und Loot, die älter sind, werden beim Einloggen entfernt, damit die gespeicherten Daten nicht endlos wachsen. Bestand und Mindestmengen sind davon nicht betroffen. \"Immer\" behält alles.",
    },
    OPT_RETENTION_FORMAT = {
        enUS = "%d months",
        deDE = "%d Monate",
    },
    OPT_RETENTION_FOREVER = {
        enUS = "Forever",
        deDE = "Immer",
    },
    OPT_LOOT_RAIDONLY_LABEL = {
        enUS = "Raids only",
        deDE = "Nur in Schlachtzügen",
    },
    OPT_LOOT_RAIDONLY_TOOLTIP = {
        enUS = "Only record loot in raid groups, not in 5-player groups.",
        deDE = "Loot nur in Schlachtzugsgruppen erfassen, nicht in 5er-Gruppen.",
    },

    -- Hauptfenster mit Reitern (seit 1.1)
    UI_TAB_OVERVIEW = { enUS = "Overview", deDE = "Übersicht" },
    UI_TAB_MEMBERS = { enUS = "Members", deDE = "Mitglieder" },
    UI_TAB_TRANSACTIONS = { enUS = "Transactions", deDE = "Vorgänge" },
    UI_TAB_STOCK = { enUS = "Stock", deDE = "Bestand" },
    UI_TAB_LOOT = { enUS = "Loot", deDE = "Loot" },
    UI_PERIOD_LABEL = { enUS = "Period:", deDE = "Zeitraum:" },
    UI_CARD_GOLD_IN = { enUS = "Gold deposited", deDE = "Gold eingezahlt" },
    UI_CARD_GOLD_OUT = { enUS = "Gold withdrawn", deDE = "Gold entnommen" },
    UI_CARD_NET = { enUS = "Balance", deDE = "Bilanz" },
    UI_CARD_NET_TOOLTIP = {
        enUS = "Deposited minus withdrawn. Repairs paid by the guild bank are not counted.",
        deDE = "Eingezahlt minus entnommen. Reparaturen auf Gildenkosten zählen nicht mit.",
    },
    UI_CARD_ITEMS = { enUS = "Items", deDE = "Gegenstände" },
    UI_CARD_ITEMS_TOOLTIP = {
        enUS = "Green: items put into the guild bank. Red: items taken out. Moving items between tabs is not counted.",
        deDE = "Grün: in die Gildenbank gelegte Gegenstände. Rot: herausgenommene. Verschieben zwischen Fächern zählt nicht mit.",
    },
    UI_FEED_TITLE = { enUS = "Latest transactions", deDE = "Letzte Vorgänge" },
    UI_FEED_COUNT = { enUS = "%d transactions  ·  %d players", deDE = "%d Vorgänge  ·  %d Spieler" },
    UI_TOP_TITLE = { enUS = "Highest balance", deDE = "Höchste Bilanz" },
    UI_TOP_HINT = { enUS = "Click to show this player's details", deDE = "Klicken, um die Details dieses Spielers zu zeigen" },
    UI_EMPTY_TITLE = { enUS = "No transactions recorded yet", deDE = "Noch keine Vorgänge gespeichert" },
    UI_EMPTY_BODY = {
        enUS = "Grindkeep reads the guild bank log every time you open the bank. Everything listed there - deposits, withdrawals and gold - then shows up here.",
        deDE = "Grindkeep liest das Log der Gildenbank jedes Mal, wenn du sie öffnest. Alles, was dort steht - Einzahlungen, Entnahmen und Gold - erscheint danach hier.",
    },
    UI_EMPTY_NEVER = {
        enUS = "The guild bank has not been opened with Grindkeep yet. Open it once - that is all it takes.",
        deDE = "Die Gildenbank wurde mit Grindkeep noch nicht geöffnet. Öffne sie einmal - mehr ist nicht nötig.",
    },
    UI_EMPTY_NO_TABS = {
        enUS = "When the log was last read (%s), your guild bank did not have a purchased tab yet. Items can only be recorded once there is a tab - gold deposits and withdrawals are recorded anyway.",
        deDE = "Beim letzten Lesen (%s) hatte eure Gildenbank noch kein gekauftes Fach. Gegenstände werden erst erfasst, wenn es ein Fach gibt - Gold-Ein- und Auszahlungen werden trotzdem mitgeschrieben.",
    },
    UI_EMPTY_NOTHING_YET = {
        enUS = "When the log was last read (%s), it was still empty. As soon as someone deposits or withdraws something, it appears here.",
        deDE = "Beim letzten Lesen (%s) stand noch nichts im Log. Sobald jemand etwas einzahlt oder entnimmt, taucht es hier auf.",
    },
    UI_EMPTY_LIMIT = {
        enUS = "Note: WoW only keeps the last 25 log entries per tab, and Grindkeep cannot see anything from before it was installed.",
        deDE = "Hinweis: WoW behält im Log nur die letzten 25 Einträge pro Fach, und was vor der Installation passiert ist, kann Grindkeep nicht sehen.",
    },
    UI_EMPTY_PERIOD = { enUS = "No transactions in this period", deDE = "Keine Vorgänge in diesem Zeitraum" },
    UI_EMPTY_PERIOD_HINT = {
        enUS = "Choose a longer period at the top, or \"All\".",
        deDE = "Wähle oben einen längeren Zeitraum oder \"Alles\".",
    },
    UI_STATUS_NEVER = { enUS = "Bank log never read - open the guild bank", deDE = "Bank-Log noch nie gelesen - Gildenbank öffnen" },
    UI_STATUS_READ = { enUS = "Bank log read %s", deDE = "Bank-Log gelesen %s" },
    UI_STATUS_TAB1 = { enUS = "1 tab", deDE = "1 Fach" },
    UI_STATUS_TABS = { enUS = "%d tabs", deDE = "%d Fächer" },
    UI_STATUS_NO_TABS = { enUS = "no tab purchased", deDE = "kein Fach gekauft" },
    UI_FILTER_PLACEHOLDER = { enUS = "Search name ...", deDE = "Name suchen ..." },
    UI_SORT_LABEL = { enUS = "Sort:", deDE = "Sortieren:" },
    UI_MEMBER_SUB = { enUS = "%d transactions  ·  last %s", deDE = "%d Vorgänge  ·  zuletzt %s" },
    UI_MEMBERS_EMPTY = {
        enUS = "No players yet. They appear here as soon as transactions are recorded - see Overview.",
        deDE = "Noch keine Spieler. Sie erscheinen hier, sobald Vorgänge gespeichert sind - siehe Übersicht.",
    },
    UI_MEMBERS_NO_MATCH = { enUS = "No player matches this name.", deDE = "Kein Spieler passt zu diesem Namen." },
    UI_TWINKS_LINE = { enUS = "Alts: %s", deDE = "Twinks: %s" },
    UI_DETAIL_RIGHTCLICK = { enUS = "right-click the name for more", deDE = "Rechtsklick auf den Namen für mehr" },
    UI_DETAIL_EMPTY = { enUS = "No transactions in the selected period.", deDE = "Keine Vorgänge im gewählten Zeitraum." },

    -- Designs (Theme.lua) und Zahnrad-Menue
    THEME_CLASSIC = { enUS = "Classic", deDE = "Klassisch" },
    THEME_MODERN = { enUS = "Modern", deDE = "Modern" },
    THEME_MINIMAL = { enUS = "Minimal", deDE = "Minimal" },
    THEME_GLASS = { enUS = "Glass", deDE = "Glas" },
    THEME_SET = { enUS = "Design: %s", deDE = "Design: %s" },
    ACCENT_THEME = { enUS = "Matching the design", deDE = "Passend zum Design" },
    ACCENT_GOLD = { enUS = "Gold", deDE = "Gold" },
    ACCENT_CLASS = { enUS = "Class color", deDE = "Klassenfarbe" },
    ACCENT_BLUE = { enUS = "Blue", deDE = "Blau" },
    ACCENT_GREEN = { enUS = "Green", deDE = "Grün" },
    ACCENT_PURPLE = { enUS = "Purple", deDE = "Lila" },
    ACCENT_RED = { enUS = "Red", deDE = "Rot" },
    MENU_GEAR_TOOLTIP = { enUS = "Design and options", deDE = "Design und Optionen" },
    MENU_DESIGN = { enUS = "Design", deDE = "Design" },
    MENU_ACCENT = { enUS = "Accent color", deDE = "Akzentfarbe" },
    MENU_ALL_OPTIONS = { enUS = "All options ...", deDE = "Alle Optionen ..." },
    MENU_HELP = { enUS = "Help", deDE = "Hilfe" },
    OPT_THEME_LABEL = { enUS = "Design", deDE = "Design" },
    OPT_THEME_TOOLTIP = {
        enUS = "Look of the Grindkeep window. Classic matches the Blizzard interface, Modern, Minimal and Glass are flat, modern styles. Also available via the gear in the window.",
        deDE = "Aussehen des Grindkeep-Fensters. Klassisch passt zur Blizzard-Oberfläche, Modern, Minimal und Glas sind flache, moderne Stile. Auch über das Zahnrad im Fenster umschaltbar.",
    },
    OPT_ACCENT_LABEL = { enUS = "Accent color", deDE = "Akzentfarbe" },
    OPT_ACCENT_TOOLTIP = {
        enUS = "Color of the active tab, selection and switches.",
        deDE = "Farbe des aktiven Reiters, der Auswahl und der Schalter.",
    },

    -- Lager-Twinks, Sammelliste, Export (seit 1.3)
    UI_TAB_COLLECT = { enUS = "Collect list", deDE = "Sammelliste" },
    MENU_EXPORT = { enUS = "Export as text ...", deDE = "Als Text exportieren ..." },
    EXPORT_BUTTON = { enUS = "Export", deDE = "Exportieren" },
    CORE_HELP_STORAGE = {
        enUS = "/gkeep lager [on|off|remove <name>] - storage alts: record this character's bags and bank",
        deDE = "/gkeep lager [an|aus|entfernen <Name>] - Lager-Twinks: Taschen und Bank dieses Charakters erfassen",
    },
    CORE_HELP_COLLECT = { enUS = "/gkeep sammel             - open the collect list", deDE = "/gkeep sammel             - Sammelliste öffnen" },
    CORE_HELP_REPORT = {
        enUS = "/gkeep bericht [sammel|bestand|vorgaenge|bilanz] - export as text (Discord, spreadsheet)",
        deDE = "/gkeep bericht [sammel|bestand|vorgaenge|bilanz] - als Text exportieren (Discord, Tabelle)",
    },
    STORAGE_ON = { enUS = "%s is now a storage alt. Bags are recorded now, the bank the next time you open it.", deDE = "%s ist jetzt ein Lager-Twink. Die Taschen sind erfasst, die Bank beim nächsten Öffnen." },
    STORAGE_OFF = { enUS = "%s is no longer counted as a storage alt.", deDE = "%s zählt nicht mehr als Lager-Twink." },
    STORAGE_REMOVED = { enUS = "Storage alt %s and its data were removed.", deDE = "Lager-Twink %s samt Daten entfernt." },
    STORAGE_NOT_FOUND = { enUS = "No storage alt named \"%s\".", deDE = "Kein Lager-Twink namens \"%s\"." },
    STORAGE_NONE = { enUS = "No storage alts yet. Log in the alt and type /gkeep lager on.", deDE = "Noch keine Lager-Twinks. Den Twink einloggen und /gkeep lager an eingeben." },
    STORAGE_LIST_HEADER = { enUS = "Storage alts:", deDE = "Lager-Twinks:" },
    STORAGE_LIST_LINE = { enUS = "  %s - %d kinds of items, bank read: %s", deDE = "  %s - %d Gegenstandsarten, Bank gelesen: %s" },
    STORAGE_BANK_NEVER = { enUS = "bank not read yet", deDE = "Bank noch nicht gelesen" },
    STORAGE_HELP = { enUS = "/gkeep lager on | off | remove <name>", deDE = "/gkeep lager an | aus | entfernen <Name>" },
    STOCK_SOURCE_LABEL = { enUS = "Show:", deDE = "Anzeigen:" },
    STOCK_SOURCE_ALL = { enUS = "All", deDE = "Alles" },
    STOCK_SOURCE_BANK = { enUS = "Guild bank", deDE = "Gildenbank" },
    STOCK_SOURCE_STORAGE = { enUS = "Storage alts", deDE = "Lager-Twinks" },
    STOCK_STORAGE_CHECK = { enUS = "This character is a storage alt", deDE = "Dieser Charakter ist ein Lager-Twink" },
    STOCK_STORAGE_CHECK_TOOLTIP = {
        enUS = "Grindkeep then records this character's bags automatically, and its bank whenever you open it. Bound items are skipped. All characters on this account see the result.",
        deDE = "Grindkeep erfasst dann die Taschen dieses Charakters automatisch und seine Bank, sobald du sie öffnest. Gebundene Gegenstände werden übersprungen. Alle Charaktere dieses Accounts sehen das Ergebnis.",
    },
    STOCK_STORAGE_NONE = {
        enUS = "No storage alts yet: log in your bank alt and tick the box above.",
        deDE = "Noch keine Lager-Twinks: Bank-Twink einloggen und oben den Haken setzen.",
    },
    STOCK_STORAGE_PREFIX = { enUS = "Storage alts:", deDE = "Lager-Twinks:" },
    STOCK_STORAGE_ENTRY = { enUS = "%s (bank: %s)", deDE = "%s (Bank: %s)" },
    STOCK_WHERE = { enUS = "Where:", deDE = "Wo liegt es:" },
    COLLECT_ADD_LABEL = { enUS = "New entry", deDE = "Neuer Eintrag" },
    COLLECT_ITEM_PLACEHOLDER = { enUS = "Item (shift-click) or text", deDE = "Gegenstand (Shift-Klick) oder Text" },
    COLLECT_AMOUNT_PLACEHOLDER = { enUS = "Amount", deDE = "Menge" },
    COLLECT_NOTE_PLACEHOLDER = { enUS = "Note (optional)", deDE = "Notiz (optional)" },
    COLLECT_ADD_BUTTON = { enUS = "Add", deDE = "Hinzufügen" },
    COLLECT_ADD_HINT = {
        enUS = "With an item, Grindkeep counts the progress itself (guild bank + storage alts). Plain text (e.g. \"Gold for tab 2\") is updated by hand via right-click.",
        deDE = "Mit Gegenstand zählt Grindkeep den Stand selbst (Gildenbank + Lager-Twinks). Freien Text (z.B. \"Gold für Fach 2\") trägst du per Rechtsklick von Hand nach.",
    },
    COLLECT_NEED_ITEM = { enUS = "Please enter an item or a text first.", deDE = "Bitte zuerst einen Gegenstand oder Text eingeben." },
    COLLECT_NEED_AMOUNT = { enUS = "Please enter an amount of at least 1.", deDE = "Bitte eine Menge von mindestens 1 eingeben." },
    COLLECT_ADD_FAILED = { enUS = "The entry could not be saved.", deDE = "Der Eintrag konnte nicht gespeichert werden." },
    COLLECT_SHOW_LABEL = { enUS = "Show:", deDE = "Anzeigen:" },
    COLLECT_SHOW_OPEN = { enUS = "Open", deDE = "Offen" },
    COLLECT_SHOW_ALL = { enUS = "All", deDE = "Alle" },
    COLLECT_SUMMARY = { enUS = "%d open  ·  %d of them reached", deDE = "%d offen  ·  davon %d erreicht" },
    COLLECT_EXPORT_BUTTON = { enUS = "Export as text", deDE = "Als Text exportieren" },
    COLLECT_EMPTY = {
        enUS = "Nothing on the list yet. Add what the guild should collect above - e.g. 100x Peacebloom for the raid.",
        deDE = "Noch nichts auf der Liste. Trag oben ein, was die Gilde sammeln soll - z.B. 100x Friedensblume für den Raid.",
    },
    COLLECT_EMPTY_OPEN = { enUS = "Everything is done. \"All\" shows finished entries.", deDE = "Alles erledigt. \"Alle\" zeigt auch abgeschlossene Einträge." },
    COLLECT_DONE = { enUS = "done", deDE = "erledigt" },
    COLLECT_REACHED = { enUS = "goal reached", deDE = "Ziel erreicht" },
    COLLECT_MISSING = { enUS = "%d missing", deDE = "es fehlen %d" },
    COLLECT_MANUAL = { enUS = "updated by hand", deDE = "Stand von Hand" },
    COLLECT_TIP_MANUAL = { enUS = "No item attached - update the progress via right-click.", deDE = "Kein Gegenstand hinterlegt - den Stand per Rechtsklick nachtragen." },
    COLLECT_TIP_NONE = { enUS = "Not found in the guild bank or on storage alts yet.", deDE = "Noch nicht in der Gildenbank oder auf Lager-Twinks gefunden." },
    COLLECT_TIP_BY = { enUS = "Added by %s on %s", deDE = "Angelegt von %s am %s" },
    COLLECT_TIP_RIGHTCLICK = { enUS = "Right-click: edit", deDE = "Rechtsklick: bearbeiten" },
    COLLECT_MENU_TARGET = { enUS = "Change amount ...", deDE = "Menge ändern ..." },
    COLLECT_MENU_HAVE = { enUS = "Set progress ...", deDE = "Stand setzen ..." },
    COLLECT_MENU_NOTE = { enUS = "Change note ...", deDE = "Notiz ändern ..." },
    COLLECT_MENU_DONE = { enUS = "Mark as done", deDE = "Als erledigt markieren" },
    COLLECT_MENU_REOPEN = { enUS = "Reopen", deDE = "Wieder öffnen" },
    COLLECT_MENU_REMOVE = { enUS = "Remove", deDE = "Entfernen" },
    COLLECT_EDIT_TARGET = { enUS = "New target amount for %s:", deDE = "Neue Zielmenge für %s:" },
    COLLECT_EDIT_NOTE = { enUS = "Note for %s:", deDE = "Notiz für %s:" },
    COLLECT_EDIT_HAVE = { enUS = "Current progress for %s:", deDE = "Aktueller Stand für %s:" },
    COLLECT_EDIT_INVALID = { enUS = "Invalid value - nothing changed.", deDE = "Ungültiger Wert - nichts geändert." },
    COLLECT_REMOVE_CONFIRM = { enUS = "Remove \"%s\" from the collect list?", deDE = "\"%s\" von der Sammelliste entfernen?" },
    EXPORT_WINDOW_TITLE = { enUS = "Grindkeep - Export", deDE = "Grindkeep - Exportieren" },
    EXPORT_WHAT = { enUS = "Content:", deDE = "Inhalt:" },
    EXPORT_HOW = { enUS = "Format:", deDE = "Format:" },
    EXPORT_KIND_COLLECT = { enUS = "Collect list", deDE = "Sammelliste" },
    EXPORT_KIND_STOCK = { enUS = "Stock", deDE = "Bestand" },
    EXPORT_KIND_TX = { enUS = "Transactions", deDE = "Vorgänge" },
    EXPORT_KIND_BALANCES = { enUS = "Balances", deDE = "Bilanzen" },
    EXPORT_FORMAT_DISCORD = { enUS = "Discord", deDE = "Discord" },
    EXPORT_FORMAT_CSV = { enUS = "Spreadsheet", deDE = "Tabelle" },
    EXPORT_FORMAT_TEXT = { enUS = "Text", deDE = "Text" },
    EXPORT_EXPLAIN_DISCORD = {
        enUS = "Formatted for Discord. Paste it into a channel as it is. Longer texts are split into parts (max. 2000 characters per message).",
        deDE = "Fertig formatiert für Discord. So wie es ist in einen Kanal einfügen. Lange Texte werden in Teile zerlegt (max. 2000 Zeichen je Nachricht).",
    },
    EXPORT_EXPLAIN_CSV = {
        enUS = "Separated by semicolons. Google Sheets: paste, then choose \"Split text to columns\". Excel: paste into A1, then Data > Text to Columns > Semicolon.",
        deDE = "Mit Semikolon getrennt. Google Tabellen: einfügen, dann \"Text in Spalten aufteilen\" wählen. Excel: in A1 einfügen, dann Daten > Text in Spalten > Semikolon.",
    },
    EXPORT_EXPLAIN_TEXT = { enUS = "Plain lines, e.g. for a forum post.", deDE = "Schlichte Zeilen, z.B. für einen Forenbeitrag." },
    EXPORT_COPY_HINT = { enUS = "The text is selected - copy it with Ctrl+C.", deDE = "Der Text ist markiert - mit Strg+C kopieren." },
    EXPORT_CHARS = { enUS = "%d characters", deDE = "%d Zeichen" },
    EXPORT_PART = { enUS = "(part %d/%d)", deDE = "(Teil %d/%d)" },
    EXPORT_FAILED = { enUS = "The export could not be created.", deDE = "Der Export konnte nicht erstellt werden." },
    EXPORT_AS_OF = { enUS = "as of %s", deDE = "Stand %s" },
    EXPORT_PERIOD_ALL = { enUS = "all time", deDE = "gesamter Zeitraum" },
    EXPORT_PERIOD_DAYS = { enUS = "last %d days", deDE = "letzte %d Tage" },
    EXPORT_TITLE_COLLECT = { enUS = "Collect list", deDE = "Sammelliste" },
    EXPORT_TITLE_STOCK = { enUS = "Stock (guild bank + storage alts)", deDE = "Bestand (Gildenbank + Lager-Twinks)" },
    EXPORT_TITLE_TX = { enUS = "Transactions", deDE = "Vorgänge" },
    EXPORT_TITLE_BALANCES = { enUS = "Balances", deDE = "Bilanzen" },
    EXPORT_STOCK_MISSING = { enUS = "Below minimum:", deDE = "Unter Mindestbestand:" },
    EXPORT_STOCK_HAVE = { enUS = "In stock:", deDE = "Vorhanden:" },
    EXPORT_MISSING = { enUS = "%d missing", deDE = "es fehlen %d" },
    EXPORT_REACHED = { enUS = "goal reached", deDE = "Ziel erreicht" },
    EXPORT_BALANCE_DETAIL = {
        enUS = "deposited %s, withdrawn %s, items +%d/-%d",
        deDE = "eingezahlt %s, entnommen %s, Gegenstände +%d/-%d",
    },
    EXPORT_EMPTY_COLLECT = { enUS = "Nothing on the collect list right now.", deDE = "Gerade steht nichts auf der Sammelliste." },
    EXPORT_EMPTY_STOCK = { enUS = "No stock recorded yet.", deDE = "Noch kein Bestand erfasst." },
    EXPORT_EMPTY_TX = { enUS = "No transactions for this selection.", deDE = "Keine Vorgänge für diese Auswahl." },
    EXPORT_EMPTY_BALANCES = { enUS = "No balances in this period.", deDE = "Keine Bilanzen in diesem Zeitraum." },
    EXPORT_COL_ITEM = { enUS = "Item", deDE = "Gegenstand" },
    EXPORT_COL_HAVE = { enUS = "Have", deDE = "Stand" },
    EXPORT_COL_TARGET = { enUS = "Target", deDE = "Ziel" },
    EXPORT_COL_MISSING = { enUS = "Missing", deDE = "Fehlt" },
    EXPORT_COL_NOTE = { enUS = "Note", deDE = "Notiz" },
    EXPORT_COL_TOTAL = { enUS = "Total", deDE = "Gesamt" },
    EXPORT_COL_BANK = { enUS = "Guild bank", deDE = "Gildenbank" },
    EXPORT_COL_STORAGE = { enUS = "Storage alts", deDE = "Lager-Twinks" },
    EXPORT_COL_MINIMUM = { enUS = "Minimum", deDE = "Mindestbestand" },
    EXPORT_COL_WHEN = { enUS = "Date", deDE = "Datum" },
    EXPORT_COL_PLAYER = { enUS = "Player", deDE = "Spieler" },
    EXPORT_COL_ACTION = { enUS = "Action", deDE = "Aktion" },
    EXPORT_COL_GOLD = { enUS = "Gold", deDE = "Gold" },
    EXPORT_COL_COUNT = { enUS = "Count", deDE = "Anzahl" },
    EXPORT_COL_WHERE = { enUS = "Where", deDE = "Wo" },
    EXPORT_COL_NET = { enUS = "Balance (gold)", deDE = "Bilanz (Gold)" },
    EXPORT_COL_GOLD_IN = { enUS = "Gold deposited", deDE = "Gold eingezahlt" },
    EXPORT_COL_GOLD_OUT = { enUS = "Gold withdrawn", deDE = "Gold entnommen" },
    EXPORT_COL_ITEMS_IN = { enUS = "Items in", deDE = "Gegenstände rein" },
    EXPORT_COL_ITEMS_OUT = { enUS = "Items out", deDE = "Gegenstände raus" },
    HELP_H_STORAGE = { enUS = "Storage alts, collect list, export", deDE = "Lager-Twinks, Sammelliste, Export" },
    HELP_T_STORAGE = {
        enUS = "No guild bank yet, or the bank is full? Log in your bank alt, open the Stock tab and tick \"This character is a storage alt\". Grindkeep then records its bags and - whenever you open it - its bank. Stock, minimum amounts and the collect list count guild bank and storage alts together.\n\nCollect list: what the guild is collecting right now, with target amount and note. With an item, the progress is counted automatically.\n\nExport (gear menu or the buttons on the pages): collect list, stock, transactions or balances as ready-made Discord text or as a spreadsheet.",
        deDE = "Noch keine Gildenbank, oder die Bank ist voll? Bank-Twink einloggen, im Reiter Bestand den Haken \"Dieser Charakter ist ein Lager-Twink\" setzen. Grindkeep erfasst dann seine Taschen und - sobald du sie öffnest - seine Bank. Bestand, Mindestmengen und Sammelliste zählen Gildenbank und Lager-Twinks zusammen.\n\nSammelliste: was die Gilde gerade sammelt, mit Zielmenge und Notiz. Mit Gegenstand zählt Grindkeep den Stand selbst.\n\nExport (Zahnrad-Menü oder die Knöpfe auf den Seiten): Sammelliste, Bestand, Vorgänge oder Bilanzen als fertiger Discord-Text oder als Tabelle.",
    },
}

local L = setmetatable({}, {
    __index = function(_, key)
        local entry = STRINGS[key]
        if not entry then return key end
        return entry[locale] or entry.enUS or key
    end,
})

_G.GrindkeepLocale = L

# Grindkeep

**Gildenbank-Protokoll, Bestand und Sammellisten für World of Warcraft (WoW Forever & Retail).**
*Guild bank log, stock tracker and collection lists for World of Warcraft (WoW Forever & Retail).*

> Status: **Beta**. Fehler bitte über die [Issues](../../issues) melden.

---

## Deutsch

Grindkeep merkt sich, was in der Gildenbank passiert, und zeigt es übersichtlich in einem Fenster mit Reitern. Es ist für Gildenleitungen und Bankverwalter gedacht, die wissen wollen, wer was eingelegt oder entnommen hat und was gerade fehlt.

### Funktionen

- **Übersicht:** Einzahlungen, Entnahmen und Bilanz der Gilde für 7, 30, 90 Tage oder den ganzen Verlauf, dazu die letzten Vorgänge und die aktivsten Mitglieder.
- **Mitglieder:** Bilanz pro Spieler, Twinks werden ihrem Hauptcharakter zugeordnet.
- **Suche:** nach Spieler, Gegenstand oder Fach, mit Filter nach Art und Zeitraum. Shift-Klick auf einen Gegenstand sucht genau diesen.
- **Bestand:** Mindestbestände festlegen und sehen, was fehlt. Zählt Gildenbank und Lager-Twinks zusammen.
- **Lager-Twinks:** eigene Charaktere als Lager markieren, Taschen und Bank werden dann automatisch erfasst.
- **Sammelliste:** Ziele wie „200 Kupfererz für die Bank“ anlegen und den Fortschritt verfolgen.
- **Export:** Sammelliste, Bestand, Vorgänge und Bilanz als Discord-Text (automatisch in Nachrichten unter 2000 Zeichen geteilt), als CSV für Excel/Google Sheets oder als reinen Text.
- **Bot-Export:** `/gkeep bot` gibt den Gildenbank-Bestand als maschinenlesbaren Text für den Grindhub-Discord-Bot aus (Format: [docs/export-format.md](docs/export-format.md)).
- **Beute:** optional, wer in Gruppe oder Raid welchen Gegenstand bekommen hat.
- **Designs:** Klassisch (passend zu WoW), Modern, Minimal und Glas, dazu eine frei wählbare Akzentfarbe (Zahnrad oben rechts).

### Bedienung

- Der Reiter **Grindkeep** an der Gildenbank öffnet das Fenster, ebenso `/gkeep` oder das Addon-Menü an der Minikarte.
- Das Protokoll wird eingelesen, sobald die Gildenbank geöffnet ist. Blizzard speichert nur die letzten Vorgänge je Fach, deshalb die Bank ruhig regelmäßig öffnen.
- `/grindkeep` funktioniert genauso wie `/gkeep`.
- `/gkeep help` zeigt alle Befehle, z. B. `/gkeep lager an`, `/gkeep sammel`, `/gkeep bericht bestand`.

### Hinweis zu WoW Forever (Beta)

Im aktuellen Forever-Beta-Client lädt ein `/reload` manchmal den vorherigen Stand der gespeicherten Einstellungen. Das betrifft alle Addons, nicht nur Grindkeep. Zum Sichern der Einstellungen lieber ausloggen statt `/reload`.

---

## English

Grindkeep records what happens in your guild bank and shows it in one tabbed window. It is meant for guild leaders and bank managers who want to know who deposited or withdrew what, and what is currently missing.

### Features

- **Overview:** guild deposits, withdrawals and net balance for 7, 30, 90 days or all time, plus the latest transactions and most active members.
- **Members:** per-player balance, alts are linked to their main.
- **Search:** by player, item or tab, filtered by type and period. Shift-click an item to search for exactly that item.
- **Stock:** set minimum stock levels and see what is missing. Counts guild bank and storage alts together.
- **Storage alts:** mark your own characters as storage; their bags and bank are recorded automatically.
- **Collection list:** goals such as "200 Copper Ore for the bank" with progress tracking.
- **Export:** collection list, stock, transactions and balances as Discord text (split into messages below 2000 characters), CSV for Excel/Google Sheets, or plain text.
- **Bot export:** `/gkeep bot` prints the guild bank contents as machine-readable text for the Grindhub Discord bot (format: [docs/export-format.md](docs/export-format.md), in German).
- **Loot:** optional record of who received which item in groups and raids.
- **Skins:** Classic (WoW style), Modern, Minimal and Glass, plus an accent colour of your choice (gear icon, top right).

The interface follows the game language: German on German clients, English otherwise.

### Usage

Open the window with the **Grindkeep** tab at the guild bank, with `/gkeep` (or `/grindkeep`), or from the addon compartment on the minimap. `/gkeep help` lists all commands.

---

## Lizenz / License

© 2026 Bobcation. All Rights Reserved. Siehe / see [LICENSE](LICENSE).
Die Nutzung im Spiel ist frei, Weiterverbreitung und Re-Uploads nur mit Erlaubnis.
Free to use in game; redistribution and re-uploads only with permission.

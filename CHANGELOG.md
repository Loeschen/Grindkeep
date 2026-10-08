# Changelog

## 1.4.1 (Beta)

- Neu: Den Code für die Gilden-Webseite gibt es jetzt per Knopf. Im Export-Fenster als viertes Format „Webseite“ (mit „Seit letztem Export“ oder „Alles“), außerdem im Zahnrad-Menü „Für die Webseite exportieren …“. `/gkeep webseite` funktioniert weiterhin.
- Der Webseiten-Code enthält jetzt die Seltenheit der Gegenstände (neue Zeilenart `I`), damit die Webseite Namen in der passenden Farbe zeigen kann. Ältere Webseiten ignorieren die neue Zeile.

## 1.4.0 (Beta)

- Neu: `/gkeep webseite` erzeugt einen Code für die Gilden-Webseite mit Gildenbank-Vorgängen, Bestand, Mindestbeständen, Sammelliste und Bankguthaben. Standard: alles seit dem letzten Export (mit einer Woche Überlappung), `/gkeep webseite alles` oder `/gkeep webseite 30` für alles bzw. die letzten 30 Tage. Die Webseite erkennt bereits bekannte Vorgänge selbst.
- Grindkeep merkt sich beim Öffnen der Gildenbank den Kontostand.
- WoW Forever: Charaktere haben Vor- und Nachnamen. Grindkeep erkennt Spieler jetzt überall über Vorname und Realm – der Nachname stört Gilden-Abgleich (Rang-Prüfung der Offiziere), Twink-Zuordnung, Mitglieder-Bilanz, Suche, Klassenfarben und Beute-Erfassung nicht mehr.
- Bestehende Twink-Zuordnungen und Summen werden beim ersten Start einmalig auf die neue Schreibweise umgestellt; gespeicherte Vorgänge bleiben unverändert.
- Behoben: „Unbekannt 0x … vor 20725 Tagen“ – leere Log-Fächer liefern Platzhalter mit ungültigem Item und einer Zeit um 1970. Die werden jetzt beim Einlesen verworfen, bereits gespeicherte Geister-Einträge beim ersten Start einmalig entfernt.
- Neu: `/gkeep namen` zeigt, wie Grindkeep deinen Namen, die Gildenliste, das Bank-Log und den letzten Addon-Absender sieht (Hilfe bei der Fehlersuche).

## 1.3.0 (Beta)

- Neues Hauptfenster mit Reitern: Übersicht, Mitglieder, Suche, Bestand, Sammelliste, Beute.
- Zahnrad-Menü mit Designs (Klassisch, Modern, Minimal, Glas) und Akzentfarben.
- Übersicht zeigt Zahlen statt Balken, dazu letzte Vorgänge und Top-Mitglieder.
- Grindkeep-Reiter an der Gildenbank (unten in der Leiste), Diagnose mit `/gkeep banktab`.
- Neu: Lager-Twinks – Taschen und Bank eigener Charaktere werden automatisch erfasst (`/gkeep lager`).
- Neu: Sammelliste mit Fortschritt (`/gkeep sammel`).
- Neu: Export als Discord-Text, CSV oder Text (`/gkeep bericht`).
- Bestand zählt Gildenbank und Lager-Twinks zusammen, mit Quellenfilter.
- Viele kleine Korrekturen (Zeitangaben, Qualitätssymbole in Namen, Scrollposition, UTF-8).

## 1.0 – 1.2

- Gildenbank-Protokoll, Suche, Mindestbestände, Twink-Zuordnung, Loot-Erfassung, Import/Export zwischen Offizieren.

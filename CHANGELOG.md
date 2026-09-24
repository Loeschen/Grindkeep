# Changelog

## Unveröffentlicht

- Neu: `/gkeep bot` (auch `/grindkeep bot`, `/gkeep export bot`) – Gildenbank-Bestand als Text für den Grindhub-Discord-Bot, versioniert, mit Zeitstempel und Prüfsumme. Format: `docs/export-format.md`.
- Neu: `/grindkeep` als zweiter Befehlsname.
- Namen: Ein Anhang „-Xyz“ gilt nur noch als Realm, wenn es der eigene oder ein verbundener Realm ist. Behebt nicht erkannte Offiziere (Forever-Roster ohne Realm), falsch zusammengelegte Beute bei Bindestrich-Nachnamen und fehlende Klassenfarben.
- Texte: kein „|“ mehr in Chat- und Hilfetexten (WoW-Steuerzeichen, verschluckte Teile z. B. bei „an|aus“).
- „Item 123“ als Ersatzname ist jetzt übersetzt („Gegenstand 123“).
- Tests mit nachgebauter WoW-API (`sh tests/run.sh`), `.pkgmeta` schließt `tests/` und `docs/` vom Paket aus.

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

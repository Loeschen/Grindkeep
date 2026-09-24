# Grindkeep: Exportformat für den Grindhub-Discord-Bot

Formatversion: **1**, seit Grindkeep 1.3.1 (noch nicht veröffentlicht).

Grindkeep schreibt den zuletzt erfassten Inhalt der Gildenbank als Text, den ein Discord-Bot einlesen kann. WoW lässt Addons weder in die Zwischenablage schreiben noch Dateien anlegen. Der Text erscheint deshalb markiert in einem Fenster und wird mit Strg+C kopiert.

## Aufruf im Spiel

```
/gkeep bot
```

Gleichwertig sind `/grindkeep bot` und `/gkeep export bot`.

`/gkeep export` ohne `bot` bleibt der bisherige Datenaustausch zwischen Grindkeep-Nutzern (Base64). Den kann der Bot nicht lesen.

Exportiert wird der Bestand aus dem letzten Bestands-Scan. Der läuft beim Öffnen der Gildenbank automatisch, von Hand mit `/gkeep stock scan`. Wurde noch nie gescannt, meldet Grindkeep das im Chat und öffnet kein Fenster. Lager-Twinks sind nicht enthalten, nur die Gildenbank.

## Aufbau

Der Text besteht aus Zeilen mit LF (`\n`) als Zeilenende. Beim Einfügen können CRLF-Zeilenenden entstehen; ein Parser muss beides annehmen. Felder werden durch Semikolon `;` getrennt, die Kodierung ist UTF-8.

```
GRINDKEEP;1;<exportiert_um>;<bestand_vom>;<gilde>;<realm>;<anzahl_zeilen>
<item_id>;<name>;<anzahl>;<fach>
<item_id>;<name>;<anzahl>;<fach>
...
END;<anzahl_zeilen>;<prüfsumme>
```

### Kopfzeile (erste Zeile)

| Nr. | Feld | Inhalt |
|---|---|---|
| 1 | Kennung | immer `GRINDKEEP` |
| 2 | Formatversion | `1` |
| 3 | exportiert_um | Zeitpunkt des Exports, Unix-Sekunden (UTC, Serverzeit) |
| 4 | bestand_vom | Zeitpunkt des Bestands-Scans, Unix-Sekunden (UTC, Serverzeit) |
| 5 | gilde | Gildenname |
| 6 | realm | eigener Realm, normalisiert (ohne Leerzeichen und Bindestriche), kann leer sein |
| 7 | anzahl_zeilen | Anzahl der Datenzeilen |

Für den Bot ist meist `bestand_vom` die wichtige Zeit, denn sie sagt, wie aktuell die Zahlen sind.

Beide Zeitpunkte sind UTC. Beispiel: `1790000420` entspricht dem 21.09.2026, 16:20:20 Uhr MESZ.

### Datenzeilen

Jede Zeile steht für einen Gegenstand in einem Fach. Liegt derselbe Gegenstand in mehreren Fächern, gibt es mehrere Zeilen.

| Nr. | Feld | Inhalt |
|---|---|---|
| 1 | item_id | numerische Item-ID |
| 2 | name | Name des Gegenstands in der Sprache des Spielclients. Kann leer sein, wenn der Client den Gegenstand noch nicht kannte; dann über die ID auflösen |
| 3 | anzahl | Stückzahl in diesem Fach (> 0) |
| 4 | fach | Nummer des Gildenbank-Fachs (1 bis 8). `0` bedeutet: Fach unbekannt (Daten aus älteren Versionen) |

Die Zeilen sind nach Fach, dann nach Item-ID sortiert. Gleicher Bestand ergibt also immer denselben Text.

### Schlusszeile (letzte Zeile)

| Nr. | Feld | Inhalt |
|---|---|---|
| 1 | Kennung | immer `END` |
| 2 | anzahl_zeilen | noch einmal die Anzahl der Datenzeilen |
| 3 | prüfsumme | Adler-32, 8 Hex-Zeichen, klein geschrieben |

Fehlt die `END`-Zeile, wurde der Text beim Kopieren abgeschnitten.

### Prüfsumme

Adler-32 (RFC 1950) über die UTF-8-Bytes aller Zeilen vor der `END`-Zeile, verbunden mit `\n`. Die Kopfzeile ist also mit abgedeckt. Es gibt kein abschließendes `\n` und kein `\r`. In Python entspricht das `zlib.adler32`.

Die Prüfsumme erkennt abgeschnittene oder versehentlich veränderte Kopien. Sie ist kein Schutz gegen absichtliche Fälschung, denn jeder kann sie neu berechnen.

### Welche Zeichen in Textfeldern vorkommen

- Keine Semikolons, Tabulatoren oder Zeilenumbrüche. Sie werden durch ein Leerzeichen ersetzt, mehrere Leerzeichen zu einem zusammengefasst.
- Kein `|`: In WoW ist das ein Steuerzeichen. Farbcodes, Links und Symbole (z. B. Qualitätsstufen) werden entfernt.
- Umlaute und andere Unicode-Zeichen bleiben erhalten (UTF-8).

## Beispiel

```
GRINDKEEP;1;1790000420;1790000000;Die Grindgilde;Testrealm;4
2770;Kupfererz;35;1
13444;Großer Manatrank;12;1
2589;Leinenstoff;40;2
2770;Kupfererz;3;2
END;4;bae52cc8
```

## Einfügen in Discord

- Discord erlaubt 2000 Zeichen pro Nachricht, mit Nitro 4000. Längere eingefügte Texte bietet Discord automatisch als Datei `message.txt` an. Der Bot sollte deshalb Nachrichtentext und `.txt`-Anhänge lesen.
- Viele Nutzer packen den Text in einen Code-Block aus drei Backticks. Der Bot sollte die Rahmenzeilen eines Code-Blocks (drei Backticks, optional mit Sprachangabe) sowie Leerzeilen ignorieren.

## Referenz-Parser (Python)

```python
import zlib

def parse_grindkeep(text: str) -> dict:
    lines = [l.strip() for l in text.replace("\r\n", "\n").split("\n")]
    fence = "`" * 3  # Code-Block-Rahmen aus Discord
    lines = [l for l in lines if l and not l.startswith(fence)]
    if len(lines) < 2:
        raise ValueError("zu kurz")
    head = lines[0].split(";")
    if head[0] != "GRINDKEEP":
        raise ValueError("keine Grindkeep-Kopfzeile")
    if head[1] != "1":
        raise ValueError(f"Formatversion {head[1]} wird nicht unterstützt")
    tail = lines[-1].split(";")
    if tail[0] != "END":
        raise ValueError("END-Zeile fehlt (Text abgeschnitten?)")
    payload = "\n".join(lines[:-1]).encode("utf-8")
    if format(zlib.adler32(payload), "08x") != tail[2].lower():
        raise ValueError("Prüfsumme stimmt nicht")
    rows = []
    for line in lines[1:-1]:
        item_id, name, count, tab = line.split(";")
        rows.append({"item_id": int(item_id), "name": name, "count": int(count), "tab": int(tab)})
    if int(head[6]) != len(rows) or int(tail[1]) != len(rows):
        raise ValueError("Zeilenzahl stimmt nicht")
    return {
        "version": 1,
        "exported_at": int(head[2]),
        "scanned_at": int(head[3]),
        "guild": head[4],
        "realm": head[5],
        "rows": rows,
    }
```

Die Lua-Gegenstücke stehen in `BotExport.lua` (`BotExport.Build`, `BotExport.Parse`) und werden in `tests/run.lua` geprüft.

## Versionierung

- Neue Felder kommen nur **hinten** an die Kopfzeile. Ein Parser für Version 1 soll zusätzliche Kopffelder ignorieren.
- Jede Änderung an Datenzeilen, Trennzeichen oder Prüfsumme erhöht die Formatversion. Ein Bot soll unbekannte Versionen ablehnen und nicht raten.

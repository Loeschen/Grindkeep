# Grindkeep → Webseite: Austauschformat GKW1

Stand: Grindkeep 1.4.2 (Beta), 08.10.2026 (Ergänzung: Klasse und Unterklasse in der I-Zeile). Ursprünglich Grindkeep 1.4.0, 30.09.2026. Erzeugt im Spiel mit `/gkeep webseite` (Standard: seit dem letzten Export mit 7 Tagen Überlappung), `/gkeep webseite alles` oder `/gkeep webseite <Tage>`. Quelle: `WebExport.lua` im Addon.

## Hülle

```
GKW1:<Base64 der Nutzlast>:<Adler-32 der Nutzlast als 8 Hex-Zeichen, klein>
```

- Base64 nach Standard-Alphabet (`A-Z a-z 0-9 + /`, Auffüllung mit `=`).
- Adler-32 über die rohen Bytes der Nutzlast (UTF-8). Stimmt die Prüfsumme nicht: Code unvollständig kopiert → ablehnen mit verständlicher Meldung.
- Beim Einfügen können Leerzeichen/Zeilenumbrüche entstehen: vor dem Zerlegen alle Whitespaces entfernen.

## Nutzlast

UTF-8-Text, Zeilen mit `\n`, Felder mit Tabulator. Erstes Feld = Zeilenart. Fehlende Zahlen stehen als `0`, fehlende Texte leer. Texte enthalten nie Tabulator/Zeilenumbruch und keine WoW-Steuerzeichen.

| Art | Felder (nach der Art) |
|---|---|
| `H` | Formatversion (`1`), Gildenname, Realm (normalisiert, ohne Leerzeichen), Exporteur (Charaktername), Exportzeit (Unix), Addon-Version, „seit“ (Unix, 0 = alles), Bankguthaben in Kupfer (leer = unbekannt), Zeitpunkt des Guthabens (Unix, 0 = unbekannt), Interface-Nummer des Clients (z. B. 120100 = Retail 12.1, 16001 = WoW Forever) |
| `T` | Zeit (Unix), Spieler (roh aus dem Bank-Log, in Forever evtl. „Vorname Nachname“), Art (`item`/`gold`), Aktion (`deposit`, `withdraw`, `move`, `repair`, …), Fach-Nr. (0 bei Gold), Fachname, ItemID (0 bei Gold), Menge, Kupfer (bei Gold), Itemname |
| `S` | ItemID, Itemname, Gesamt, davon Gildenbank, davon Lager-Twinks, Mindestbestand (0 = keiner) |
| `C` | Eintrag-ID (je Gilde im Addon), ItemID (0 = freier Text, z. B. „Gold für Fach 3“), Name/Text, Ziel, Vorhanden, Erledigt (`0`/`1`), Notiz |
| `I` | ItemID, Qualität (`0`–`7`: grau, weiß, grün, blau, lila, orange, Artefakt, Erbstück), **optional** classID, subclassID. **Seit Grindkeep 1.4.1**, eine Zeile je Gegenstand aus T/S/C, nur wenn die Qualität bekannt ist. classID und subclassID **seit 1.4.2** (siehe unten). Codes aus 1.4.0 (ohne I-Zeilen) und 1.4.1 (I-Zeilen mit zwei Feldern) bleiben gültig. Zählt **nicht** in `E`. |
| `E` | Anzahl T, Anzahl S, Anzahl C (Kontrolle: muss zu den gelesenen Zeilen passen) |

### Klasse und Unterklasse in der I-Zeile (seit 1.4.2)

```
I	<ItemID>	<Qualität>	<classID>	<subclassID>
```

- Quelle: `C_Item.GetItemInfoInstant(itemID)`, Rückgabewerte 6 und 7. Das braucht keine Serverabfrage.
- Beide Felder stehen zusammen oder gar nicht. Kennt der Client den Gegenstand nicht, endet die Zeile wie in 1.4.1 nach der Qualität. Die Webseite soll dann auf ihre eigene Zuordnung zurückfallen.
- `0` ist ein echter Wert (classID 0 = Verbrauchbares). Ein fehlendes Feld heißt „unbekannt“, nicht `0`.
- Die Zahlen sind die Blizzard-Kennungen (`Enum.ItemClass`, je Klasse eigene Unterklassen). Beispiele: `7 7` = Handwerkswaren › Metall & Stein, `7 5` = Handwerkswaren › Stoff, `2 7` = Waffe › Einhandschwert, `0 1` = Verbrauchbares › Trank.
- Eine I-Zeile entsteht weiterhin nur, wenn die Qualität bekannt ist. Ein leeres Qualitätsfeld würde als `0` (grau) gelesen.
- Ältere Leser, die nur zwei Felder lesen, übersehen die Zusatzfelder einfach. Die Formatversion bleibt `1`.

Unbekannte Zeilenarten ignorieren (spätere Versionen dürfen Arten ergänzen). Die Formatversion bleibt `1` (die I-Zeile ist eine Ergänzung). Andere Formatversion als `1`: ablehnen mit Hinweis „Grindkeep bzw. Webseite aktualisieren“.

## Wichtige Eigenheiten

- **Zeiten sind Näherungen.** WoW liefert im Bank-Log nur „vor X Jahren/Monaten/Tagen/Stunden“. Derselbe Vorgang kann in zwei Exporten um bis zu ~1,5 Std. (jung) bzw. ~10 % seines Alters (älter als 28 Tage, mindestens 3 Tage) abweichen. Grindkeep selbst gleicht so ab: `Toleranz = 5400 s`, ab einem Alter von 28 Tagen `max(3 Tage, 10 % des Alters)`.
- **Doppelt-Schutz:** Inhaltsschlüssel ohne Zeit = (Art, Aktion mit `withdrawal`→`withdraw`, Spielerschlüssel, ItemID bzw. Kupfer, Menge, Fach). Ein neuer Vorgang gilt als bekannt, wenn ein gespeicherter mit gleichem Schlüssel innerhalb der Toleranz liegt; jeder gespeicherte wird höchstens einmal zugeordnet (dem zeitlich nächsten). Mehrere gleiche Vorgänge in derselben Stunde bleiben so einzeln.
- **Spielerschlüssel (wie Grindkeep 1.4.0):** Vorname (erstes Wort), und nur bei einem fremden Realm `-Realm` dahinter. Leer/`?`/`Unbekannt` = kein Spieler.
- **Überlappung ist Absicht:** Der Standard-Export enthält die letzten 7 Tage vor dem letzten Export erneut. Der Doppelt-Schutz muss das abfangen.
- **Bestand und Sammelliste sind Momentaufnahmen:** bei jedem Import komplett ersetzen (mit „Stand: <Exportzeit>, von <Exporteur>“).
- Geister-Einträge (ohne Spieler und ohne echte Item-ID/Menge, Zeit vor 2000) filtert Grindkeep schon heraus; die Webseite verwirft sie trotzdem defensiv.

## Beispiel

`GKW1-beispiel.txt` (daneben) dekodiert zu:

```
H	1	Vermächtnis der Allianz	Nethergarde	Hanschen	1790720000	1.4.0	0	22000000	0	120100
T	1790000000	Hanschen	item	deposit	1	Fach 1	13888	200	0	Schwarzer Barrakuda
T	1790000100	Krutolo Zitterhand	gold	withdraw	0		0	0	150000
S	13888	Schwarzer Barrakuda	200	200	0	0
C	1	2770	Kupfererz	200	120	0	für Fach 2
C	2	0	Gold für Fach 3	1	0	0
E	2	1	2
```

Prüfsumme des Beispiels: `3d925c29`.

Das Beispiel stammt aus 1.4.0 und hat deshalb keine I-Zeilen. Ab 1.4.2 sehen I-Zeilen so aus (vor der `E`-Zeile, nicht mitgezählt):

```
I	2770	1	7	7
I	19019	5	2	7
I	99998	3
```

Die letzte Zeile zeigt einen Gegenstand, den der Client nicht kannte: Qualität aus dem Link, ohne Klasse.

## Referenz-Dekoder (Python)

```python
import base64, re

def adler32_hex(data: bytes) -> str:
    a, b = 1, 0
    for byte in data:
        a = (a + byte) % 65521
        b = (b + a) % 65521
    return f"{b * 65536 + a:08x}"

def decode_gkw(code: str) -> list[list[str]]:
    code = re.sub(r"\s+", "", code)
    prefix, b64, chk = code.split(":")
    if prefix != "GKW1":
        raise ValueError("Kein Grindkeep-Code (GKW1)")
    payload = base64.b64decode(b64)
    if adler32_hex(payload) != chk.lower():
        raise ValueError("Code unvollständig kopiert (Prüfsumme passt nicht)")
    return [line.split("\t") for line in payload.decode("utf-8").split("\n")]
```

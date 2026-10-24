"""Gegentest: Grindkeep-Webseiten-Codes mit dem Parser der Webseite lesen.

Aufruf:  python3 tests/check_gkw.py <Pfad zu grindhub-bot> <Datei mit Codes>
Die Datei schreibt tests/run.lua, wenn GK_CODES_OUT gesetzt ist (eine Zeile je
Code: Profil<TAB>Art<TAB>Code). Zusaetzlich wird das offizielle 1.4.0-Beispiel
docs/grindkeep/GKW1-beispiel.txt aus grindhub-bot gelesen (Abwaertskompatibilitaet).
sh tests/run.sh ruft das automatisch auf, wenn GRINDHUB_BOT gesetzt ist.
"""

import pathlib
import sys

bot = pathlib.Path(sys.argv[1]).resolve()
sys.path.insert(0, str(bot))
from grindhub.services import gkw  # noqa: E402

failures = 0


def check(cond, msg):
    global failures
    if not cond:
        failures += 1
        print(f"FAIL [gkw.py] {msg}")


EXPECTED = {2770: (7, 7), 19019: (2, 7), 2589: (7, 5), 13444: (0, 1)}

for line in pathlib.Path(sys.argv[2]).read_text(encoding="utf-8").splitlines():
    profile, kind, code = line.split("\t")
    try:
        export = gkw.parse(code)
    except gkw.GkwError as e:
        check(False, f"{profile}/{kind}: abgelehnt: {e}")
        continue
    label = f"{profile}/{kind}"
    check(export.header.addon_version == "1.4.2", f"{label}: Addon-Version {export.header.addon_version}")
    check(export.qualities.get(19019) == 5, f"{label}: Qualitaet 19019 = {export.qualities.get(19019)}")
    check(99999 not in export.qualities, f"{label}: unbekannter Gegenstand ohne Qualitaet")
    if kind == "klassen":
        for item_id, cls in EXPECTED.items():
            check(export.classes.get(item_id) == cls, f"{label}: Klasse {item_id} = {export.classes.get(item_id)}")
    else:
        check(export.classes == {}, f"{label}: ohne Klassen erwartet, bekommen {export.classes}")
    print(f"[gkw.py] {label}: {len(export.transactions)} T, {len(export.stock)} S, {len(export.collect)} C, "
          f"{len(export.qualities)} Qualitaeten, {len(export.classes)} Klassen")

# Alter Code aus 1.4.0 (ohne I-Zeilen) muss weiter gelten
old = gkw.parse((bot / "docs/grindkeep/GKW1-beispiel.txt").read_text(encoding="utf-8"))
check(old.header.addon_version == "1.4.0" and not old.qualities and not old.classes, "1.4.0-Beispiel")
print(f"[gkw.py] 1.4.0-Beispiel: {len(old.transactions)} T, {len(old.stock)} S, {len(old.collect)} C")

# Spielerschluessel: Webseite (player_key) und Addon (Names.Key, siehe
# tests/run.lua) muessen dieselben Schluessel bilden. Eigener Realm "Testrealm".
SAME_KEYS = {
    "Bobcation Immolation": "Bobcation Immolation",
    "Bobcation Immolation-Testrealm": "Bobcation Immolation",
    "Anna Meier-Schulz": "Anna Meier-Schulz",
    "Anna Meier-Schulz-Testrealm": "Anna Meier-Schulz",
    "Anna Krause": "Anna Krause",
    "  Anna   Krause ": "Anna Krause",
    "Krutolo Zitterhand-Fremdrealm": "Krutolo Zitterhand-Fremdrealm",
    "?": "",
}
for raw, expected in SAME_KEYS.items():
    got = gkw.player_key(raw, "Testrealm")
    check(got == expected, f"player_key({raw!r}) = {got!r}, Addon erwartet {expected!r}")
check(gkw.player_key("Anna Meier-Schulz", "Testrealm") != gkw.player_key("Anna Krause", "Testrealm"),
      "Anna Meier-Schulz und Anna Krause getrennt")
print(f"[gkw.py] Spielerschluessel: {len(SAME_KEYS)} Faelle gegen das Addon geprueft")

print(f"[gkw.py] {'alles in Ordnung' if failures == 0 else str(failures) + ' Fehler'}")
sys.exit(1 if failures else 0)

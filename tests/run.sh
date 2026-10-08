#!/bin/sh
# Alle Tests: Syntax (luac5.1 -p), statische Pruefungen, Laufzeit-Tests
# fuer WoW Forever und Retail. Mit GRINDHUB_BOT=<Pfad zu grindhub-bot>
# zusaetzlich der Gegentest mit dem Parser der Webseite (gkw.py).
# Aufruf: sh tests/run.sh
set -e
cd "$(dirname "$0")/.."
for f in *.lua tests/*.lua; do
    luac5.1 -p "$f"
done
echo "[syntax] alle Dateien fehlerfrei"
lua5.1 tests/static.lua
if [ -n "$GRINDHUB_BOT" ]; then
    codes=$(mktemp)
    GK_CODES_OUT="$codes" lua5.1 tests/run.lua forever
    GK_CODES_OUT="$codes" lua5.1 tests/run.lua retail
    python3 tests/check_gkw.py "$GRINDHUB_BOT" "$codes"
    rm -f "$codes"
else
    lua5.1 tests/run.lua forever
    lua5.1 tests/run.lua retail
    echo "[gkw.py] uebersprungen (GRINDHUB_BOT nicht gesetzt)"
fi

#!/bin/sh
# Alle Tests: Syntax (luac5.1 -p), statische Pruefungen, Laufzeit-Tests
# fuer WoW Forever und Retail. Aufruf: sh tests/run.sh
set -e
cd "$(dirname "$0")/.."
for f in *.lua tests/*.lua; do
    luac5.1 -p "$f"
done
echo "[syntax] alle Dateien fehlerfrei"
lua5.1 tests/static.lua
lua5.1 tests/run.lua forever
lua5.1 tests/run.lua retail

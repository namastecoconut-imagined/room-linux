#!/usr/bin/env bash
# What Room hears, kept as audio: the exact sound sent to Deepgram for each request, next to what came back.
#   heard on     keep the next requests (the last 10, in ~/room-heard)
#   heard off    stop keeping them
#   heard        list them        ·   heard play 3   play number 3
D=~/room-heard
case "$1" in
  on)  mkdir -p "$D" && touch "$D/on" && echo "✓ Keeping what Room hears in ~/room-heard (the last 10). Now talk to it." ;;
  off) rm -f "$D/on" && echo "✓ Stopped keeping (what's there stays — delete ~/room-heard to clear it)" ;;
  play) f=$(ls "$D"/*.wav 2>/dev/null | sed -n "${2:-1}p"); [ -n "$f" ] && { echo "▶ $f"; pw-play "$f"; } || echo "No number ${2:-1}" ;;
  *)
    [ -f "$D/on" ] && echo "(keeping: on)" || echo "(keeping: off — 'heard on' to start)"
    i=0
    for t in "$D"/*.txt; do
      [ -f "$t" ] || continue; i=$((i+1))
      python3 - "$t" "$i" <<'P'
import json, sys
d = json.load(open(sys.argv[1]))
print(f"{sys.argv[2]:>2}. {d.get('at','')}  heard: {d.get('heard')!r}" + (f"   (earlier guess: {d['earlier_guess']!r})" if d.get('earlier_guess') else ""))
P
    done
    [ $i -gt 0 ] && echo "Play one with: heard play <number>" ;;
esac

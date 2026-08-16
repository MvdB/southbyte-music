#!/usr/bin/env bash
# A/B: Kurz-Caption (Kochbuchform, southbyte-music-Stand) gegen Langform
# (music-caption-rewriter). Gleiche Lyrics, gleiche Seeds, gleiche Frames.
set -u
HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENDPUNKT="http://127.0.0.1:8011/v1/audio/speech"
MODELL="/hf_models/MiniMaxAI--MiniMax-Music3"
FRAMES=1750

for VARIANTE in a_kurz b_lang; do
  for SEED in 7 21; do
    ZIEL="$HIER/out_${VARIANTE}_seed${SEED}.wav"
    [ -s "$ZIEL" ] && { echo "[$VARIANTE seed$SEED] existiert schon, uebersprungen"; continue; }
    python3 - "$HIER" "$VARIANTE" "$SEED" "$FRAMES" "$MODELL" > "$HIER/anfrage.json" <<'PY'
import json, sys, pathlib
hier, variante, seed, frames, modell = sys.argv[1:6]
h = pathlib.Path(hier)
json.dump({
    "model": modell,
    "input": h.joinpath("lyrics.txt").read_text(),
    "instructions": h.joinpath(f"caption_{variante}.txt").read_text(),
    "response_format": "wav",
    "seed": int(seed),
    "max_new_tokens": int(frames),
}, sys.stdout)
PY
    START=$(date +%s)
    HTTP=$(curl -s -o "$ZIEL" -w '%{http_code}' -m 1800 "$ENDPUNKT" \
             -H 'Content-Type: application/json' --data-binary @"$HIER/anfrage.json")
    DAUER=$(( $(date +%s) - START ))
    GROESSE=$(stat -c%s "$ZIEL" 2>/dev/null || echo 0)
    echo "[$VARIANTE seed$SEED] http=$HTTP dauer=${DAUER}s bytes=$GROESSE"
    if [ "$HTTP" != "200" ]; then echo "  FEHLER: $(head -c 300 "$ZIEL")"; fi
  done
done
echo "FERTIG"

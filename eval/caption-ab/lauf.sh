#!/usr/bin/env bash
# Caption-Vergleich: gleiche Lyrics, gleiche Seeds, gleiche Framezahl, nur die
# Caption wechselt. Drei Arme:
#   a_kurz    Kochbuch-Kurzform, vier Zeilen
#   b_lang    frei geschriebene Langform
#   c_biblio  Langform, abgeleitet aus der Vorlagenbibliothek des Skills
#
# Aufruf:
#   ./lauf.sh                     alle drei Arme, Seeds 7 und 21
#   ./lauf.sh c_biblio            nur ein Arm
#   SEEDS=7 SUFFIX=_kontrolle ./lauf.sh b_lang    Kontrollauf ohne Ueberschreiben
#
# Vorhandene Dateien werden uebersprungen, nicht neu erzeugt.
set -u
HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENDPUNKT="${ENDPUNKT:-http://127.0.0.1:8011/v1/audio/speech}"
MODELL="${MODELL:-/hf_models/MiniMaxAI--MiniMax-Music3}"
FRAMES="${FRAMES:-1750}"
SEEDS="${SEEDS:-7 21}"
SUFFIX="${SUFFIX:-}"
VARIANTEN="${*:-a_kurz b_lang c_biblio}"

for VARIANTE in $VARIANTEN; do
  CAPTION="$HIER/caption_${VARIANTE}.txt"
  [ -s "$CAPTION" ] || { echo "[$VARIANTE] keine Caption unter $CAPTION"; exit 1; }
  for SEED in $SEEDS; do
    ZIEL="$HIER/out_${VARIANTE}_seed${SEED}${SUFFIX}.wav"
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
    # -L, sonst meldet stat bei einem Symlink dessen eigene Groesse (die Laenge
    # des Zielpfads) statt der der Datei — 63 Byte fuer ein 9-MB-WAV.
    GROESSE=$(stat -Lc%s "$ZIEL" 2>/dev/null || echo 0)
    echo "[$VARIANTE seed$SEED$SUFFIX] http=$HTTP dauer=${DAUER}s bytes=$GROESSE"
    if [ "$HTTP" != "200" ]; then echo "  FEHLER: $(head -c 300 "$ZIEL")"; fi
  done
done
echo "FERTIG"

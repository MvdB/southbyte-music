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
#
# Neben jede Generierung schreibt das Skript den Stand des Servers, der sie
# erzeugt hat, nach stand.tsv -- siehe "Serverstand" weiter unten.
set -u
HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENDPUNKT="${ENDPUNKT:-http://127.0.0.1:8011/v1/audio/speech}"
MODELL="${MODELL:-/hf_models/MiniMaxAI--MiniMax-Music3}"
FRAMES="${FRAMES:-1750}"
SEEDS="${SEEDS:-7 21}"
SUFFIX="${SUFFIX:-}"
VARIANTEN="${*:-a_kurz b_lang c_biblio}"
MUSIK_CONTAINER="${MUSIK_CONTAINER:-southbyte-music}"
PROTOKOLL="${PROTOKOLL:-$HIER/stand.tsv}"

# ── Serverstand ──────────────────────────────────────────────────────────
# Ein Wechsel des Serverstands veraendert das Ergebnis bei festem Seed
# nachweislich, zwei Laeufe auf demselben Stand sind dagegen bis auf jede
# Stelle identisch (ERGEBNIS.md, Abschnitt "Determinismus und Serverstand").
# Der Stand gehoert deshalb neben die Messwerte -- und zwar der abgeholte
# Digest, nicht die Bildmarke: Wer mit `0.1` oder `latest` faehrt und
# Watchtower aktualisieren laesst, hat unter derselben Marke morgen ein
# anderes Image. Aus demselben Grund wird vor *und* nach jeder Generierung
# gefragt: Ein Neustart mitten im Lauf faellt sonst niemandem auf.
#
# Rueckgabe sind drei Tabulatorfelder: Digest, Version, Commit.
stand() {
  # Nur aussagekraeftig, wenn der Dienst auf dieser Maschine in Docker laeuft.
  case "$ENDPUNKT" in
    *//127.0.0.1[:/]* | *//localhost[:/]*) ;;
    *) printf 'extern\t-\t-'; return ;;
  esac
  command -v docker >/dev/null 2>&1 || { printf 'ohne-docker\t-\t-'; return; }
  BILD=$(docker inspect --format '{{.Image}}' "$MUSIK_CONTAINER" 2>/dev/null)
  [ -n "$BILD" ] || { printf 'kein-container\t-\t-'; return; }
  # RepoDigests ist leer, wenn das Image lokal gebaut und nie geholt wurde --
  # dann bleibt die Image-ID als Kennung. Die Labels fehlen bei einem
  # Handbau ebenfalls, deshalb jeweils mit Ausweichwert.
  docker image inspect "$BILD" --format \
    '{{if .RepoDigests}}{{index .RepoDigests 0}}{{else}}{{.Id}}{{end}}	{{with index .Config.Labels "org.opencontainers.image.version"}}{{.}}{{else}}-{{end}}	{{with index .Config.Labels "org.opencontainers.image.revision"}}{{.}}{{else}}-{{end}}' \
    2>/dev/null || printf 'unbekannt\t-\t-'
}

[ -s "$PROTOKOLL" ] || printf 'zeit\tvariante\tlauf\thttp\tdauer_s\tbytes\tdigest\tversion\tcommit\n' > "$PROTOKOLL"

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
    VOR=$(stand)
    START=$(date +%s)
    HTTP=$(curl -s -o "$ZIEL" -w '%{http_code}' -m 1800 "$ENDPUNKT" \
             -H 'Content-Type: application/json' --data-binary @"$HIER/anfrage.json")
    DAUER=$(( $(date +%s) - START ))
    NACH=$(stand)
    # -L, sonst meldet stat bei einem Symlink dessen eigene Groesse (die Laenge
    # des Zielpfads) statt der der Datei — 63 Byte fuer ein 9-MB-WAV.
    GROESSE=$(stat -Lc%s "$ZIEL" 2>/dev/null || echo 0)
    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "$(date -Is)" "$VARIANTE" "seed${SEED}${SUFFIX}" "$HTTP" "$DAUER" "$GROESSE" "$VOR" \
      >> "$PROTOKOLL"
    echo "[$VARIANTE seed$SEED$SUFFIX] http=$HTTP dauer=${DAUER}s bytes=$GROESSE stand=$(printf '%s' "$VOR" | cut -f1)"
    # Bei einer abgelehnten Verbindung legt curl die Datei gar nicht erst an;
    # ohne die Abfrage meldet head dann seinerseits einen Fehler und verdeckt
    # den eigentlichen.
    if [ "$HTTP" != "200" ]; then
      echo "  FEHLER: $([ -f "$ZIEL" ] && head -c 300 "$ZIEL" || echo "keine Antwort (http=$HTTP)")"
    fi
    if [ "$VOR" != "$NACH" ]; then
      # Der Server ist waehrend der Generierung ausgetauscht worden. Welcher
      # Stand das Stueck erzeugt hat, ist damit offen -- die Datei taugt nicht
      # als Beleg und wird zur Seite gelegt, statt still stehenzubleiben.
      mv -f "$ZIEL" "$ZIEL.standwechsel" 2>/dev/null
      printf '%s\t%s\t%s\tSTANDWECHSEL\t%s\t%s\t%s\n' \
        "$(date -Is)" "$VARIANTE" "seed${SEED}${SUFFIX}" "$DAUER" "$GROESSE" "$NACH" >> "$PROTOKOLL"
      echo "  ACHTUNG: Serverstand hat waehrend der Generierung gewechselt."
      echo "    vorher : $(printf '%s' "$VOR"  | cut -f1)"
      echo "    nachher: $(printf '%s' "$NACH" | cut -f1)"
      echo "    -> $ZIEL.standwechsel, nicht als Messwert verwenden."
    fi
  done
done
echo "FERTIG — Serverstand je Generierung in ${PROTOKOLL#"$HIER"/}"

#!/usr/bin/env bash
# Prueft ein Serving-Image auf echter Hardware — der Schritt, den die CI nicht
# kann.
#
# Die CI baut beide Architekturen und stellt damit fest, dass sich alles
# installieren laesst. Was sie NICHT feststellen kann: ob das Ding auf einer
# GPU auch laeuft. Ihre Runner haben keine. Genau da faellt aber die Sorte
# Fehler an, die spaeter teuer wird — ein Kernel, der auf sm_120 nicht
# vorliegt, ein Modell, das nicht in den Speicher passt, ein Nutzerwechsel, der
# einen Cache-Pfad unschreibbar macht.
#
# Dieses Skript schliesst die Luecke: Image ziehen, starten, warten, ein kurzes
# Stueck als WAV und eines als MP3 erzeugen, beide Kopfdaten pruefen,
# aufraeumen. Am Ende steht eine Aussage, die man verantworten kann.
#
#   ./pruefe_image.sh                                   # lokal gebautes Image
#   ./pruefe_image.sh ghcr.io/mvdb/southbyte-music:main # veroeffentlichtes
set -euo pipefail

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

IMAGE="${1:-${IMAGE:-southbyte-music:lokal}}"
HF_MODELS_DIR="${HF_MODELS_DIR:-$HOME/hf_models}"
MODEL_DIR="${MODEL_DIR:-MiniMaxAI--MiniMax-Music3}"
NAME="${NAME:-southbyte-music-pruefung}"
PORT="${PORT:-8019}"
# 250 Frames sind 10 s Musik und rund 85 s Rechenzeit. Genug, um zu beweisen,
# dass die ganze Kette traegt, ohne eine Viertelstunde zu binden.
FRAMES="${FRAMES:-250}"
# Der MP3-Nachweis braucht nur einen gueltigen Frame-Kopf, kein ganzes Stueck.
# 100 Frames sind 4 s Musik und rund 35 s Rechenzeit — der Rest waere Wartezeit
# fuer eine Aussage, die schon nach dem ersten Kopf feststeht.
MP3_FRAMES="${MP3_FRAMES:-100}"
WARTEN="${WARTEN:-600}"

AUS="$(mktemp -d)"
aufraeumen() {
  docker rm -f "${NAME}" >/dev/null 2>&1 || true
  rm -rf "${AUS}"
}
trap aufraeumen EXIT

echo "Pruefe ${IMAGE}"
echo "  Modell : ${HF_MODELS_DIR}/${MODEL_DIR}"
echo "  Port   : ${PORT}"

[[ -d "${HF_MODELS_DIR}/${MODEL_DIR}" ]] || {
  echo "FEHLER: Modellverzeichnis fehlt: ${HF_MODELS_DIR}/${MODEL_DIR}" >&2; exit 1; }

echo
echo "── 1/6  Architektur und Herkunft"
docker image inspect "${IMAGE}" >/dev/null 2>&1 || docker pull "${IMAGE}"
docker image inspect "${IMAGE}" --format '  {{.Os}}/{{.Architecture}}  {{.Id}}'
docker image inspect "${IMAGE}" --format '{{range $k,$v := .Config.Labels}}{{$k}}={{$v}}
{{end}}' | grep -E '^(de\.southbyte|org\.opencontainers\.image\.(version|revision))' | sed 's/^/  /' || true

echo
echo "── 2/6  Laeuft nicht als root"
NUTZER="$(docker run --rm --entrypoint id "${IMAGE}" -u)"
if [[ "${NUTZER}" == "0" ]]; then
  echo "  FEHLER: Container laeuft als root (uid 0)" >&2; exit 1
fi
echo "  uid ${NUTZER} — nicht root, gut."

echo
echo "── 3/6  Start"
docker rm -f "${NAME}" >/dev/null 2>&1 || true
# Der read-only eingebundene Modellspeicher ist Absicht und Teil der Pruefung:
# so laeuft es auch in Kubernetes, wo der Server das Volume nur lesen darf.
docker run -d --name "${NAME}" \
  --gpus all --ipc=host \
  -p "${PORT}:8000" \
  -v "${HF_MODELS_DIR}:/hf_models:ro" \
  -v "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/overrides/qwen_7B_config.json:/hf_models/${MODEL_DIR}/qwen_7B/qwen_7B/config.json:ro" \
  -e MODEL_PATH="/hf_models/${MODEL_DIR}" \
  -e TRANSFORMERS_OFFLINE=1 -e HF_HUB_OFFLINE=1 \
  "${IMAGE}" >/dev/null

echo -n "  warte auf /health (bis ${WARTEN} s) "
BEGONNEN=$SECONDS
while (( SECONDS - BEGONNEN < WARTEN )); do
  if curl -fsS --max-time 5 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
    echo " bereit nach $((SECONDS - BEGONNEN)) s"
    break
  fi
  if ! docker ps --format '{{.Names}}' | grep -qx "${NAME}"; then
    echo
    echo "  FEHLER: Container ist gestorben. Letzte Zeilen:" >&2
    docker logs --tail 30 "${NAME}" >&2
    exit 1
  fi
  echo -n "."
  sleep 5
done
curl -fsS --max-time 5 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1 || {
  echo; echo "  FEHLER: nach ${WARTEN} s nicht bereit" >&2
  docker logs --tail 30 "${NAME}" >&2; exit 1; }

echo
echo "── 4/6  Ein Stueck erzeugen (${FRAMES} Frames)"
BEGONNEN=$SECONDS
CODE=$(curl -s -o "${AUS}/probe.wav" -w '%{http_code}' --max-time 900 \
  "http://127.0.0.1:${PORT}/v1/audio/speech" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"/hf_models/${MODEL_DIR}\",
       \"input\":\"[Chorus]\\nSouth Byte - a heartbeat in the wire\",
       \"instructions\":\"Basic Attributes: bpm is 150, key is E minor, Melodic Heavy Metal.\\nVocals: clean powerful female lead.\",
       \"response_format\":\"wav\",\"max_new_tokens\":${FRAMES},\"seed\":7}")
DAUER=$((SECONDS - BEGONNEN))
[[ "${CODE}" == "200" ]] || {
  echo "  FEHLER: HTTP ${CODE}" >&2; head -c 400 "${AUS}/probe.wav" >&2; echo; exit 1; }
echo "  HTTP 200 in ${DAUER} s"

echo
echo "── 5/6  Ist das wirklich Audio?"
# Eine 200er-Antwort beweist nur, dass etwas zurueckkam. Erst der Kopf der
# Datei beweist, dass es Stereo mit 32 kHz ist — genau das, was das Modell
# liefern soll.
python3 - "${AUS}/probe.wav" <<'PY'
import pathlib
import struct
import sys

d = pathlib.Path(sys.argv[1]).read_bytes()
if d[:4] != b"RIFF" or d[8:12] != b"WAVE":
    sys.exit(f"FEHLER: keine WAV-Datei ({d[:12]!r})")
i = d.find(b"fmt ")
kanaele, rate = struct.unpack("<HI", d[i + 10 : i + 16])
j = d.find(b"data")
laenge = struct.unpack("<I", d[j + 4 : j + 8])[0]
sekunden = laenge / (rate * kanaele * 2)
print(f"  {rate} Hz, {kanaele} Kanaele, {sekunden:.1f} s, {len(d) / 1024:.0f} KB")
if kanaele != 2:
    sys.exit(f"FEHLER: {kanaele} Kanal/Kanaele statt Stereo")
if rate != 32000:
    sys.exit(f"FEHLER: {rate} Hz statt 32000")
if sekunden < 1:
    sys.exit("FEHLER: Ausgabe ist zu kurz, um echt zu sein")
PY

echo
echo "── 6/6  Kommt MP3 stereo zurueck? (${MP3_FRAMES} Frames)"
# Bis v0.1.2 kodierte sglang-omni MP3, FLAC, Opus und AAC fest in Mono und warf
# dabei die Haelfte des Signals weg, ohne zu warnen (docs/upstream-issue-mono.md).
# #1558 behebt das, aber ob der Fix im ausgelieferten Image wirklich steckt,
# zeigt keine Versionsnummer — nur eine echte Antwort dieses Servers.
BEGONNEN=$SECONDS
CODE=$(curl -s -o "${AUS}/probe.mp3" -w '%{http_code}' --max-time 900 \
  "http://127.0.0.1:${PORT}/v1/audio/speech" \
  -H 'Content-Type: application/json' \
  -d "{\"model\":\"/hf_models/${MODEL_DIR}\",
       \"input\":\"[Chorus]\\nSouth Byte - a heartbeat in the wire\",
       \"instructions\":\"Basic Attributes: bpm is 150, key is E minor, Melodic Heavy Metal.\\nVocals: clean powerful female lead.\",
       \"response_format\":\"mp3\",\"max_new_tokens\":${MP3_FRAMES},\"seed\":7}")
DAUER=$((SECONDS - BEGONNEN))
[[ "${CODE}" == "200" ]] || {
  echo "  FEHLER: HTTP ${CODE}" >&2; head -c 400 "${AUS}/probe.mp3" >&2; echo; exit 1; }
echo "  HTTP 200 in ${DAUER} s"
# Dieselbe Kanalpruefung, die wav_zu_mp3.sh auf seine eigene Umwandlung anwendet.
python3 "${HIER}/pruefe_mp3.py" "${AUS}/probe.mp3"

echo
echo "BESTANDEN — ${IMAGE} laeuft auf dieser Hardware und erzeugt Musik,"
echo "            stereo sowohl als WAV wie als MP3."

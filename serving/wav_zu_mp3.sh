#!/usr/bin/env bash
# Wandelt ein erzeugtes WAV in ein MP3 um — und behaelt dabei das Stereobild.
#
# SGLang-Omni v0.1.3 liefert nicht-streamende MP3-Antworten bereits stereo.
# Das Skript bleibt fuer vorhandene WAV-Dateien und eine bewusst gewaehlte Bitrate
# nuetzlich. Das ffmpeg dafuer steckt bereits im Serving-Image (imageio-ffmpeg,
# aarch64, mit libmp3lame) — kein zusaetzliches Paket auf dem Host noetig.
#
#   ./wav_zu_mp3.sh lied.wav                # -> lied.mp3, 192 kbit/s
#   ./wav_zu_mp3.sh lied.wav fertig.mp3 320 # eigener Name und eigene Bitrate
set -euo pipefail

HIER="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

EIN="${1:?Aufruf: $0 <eingabe.wav> [ausgabe.mp3] [bitrate-kbit]}"
AUS="${2:-${EIN%.*}.mp3}"
BITRATE="${3:-192}"
IMAGE="${IMAGE:-southbyte-music:lokal}"

[[ -f "$EIN" ]] || { echo "FEHLER: $EIN gibt es nicht" >&2; exit 1; }

VERZ="$(cd "$(dirname "$EIN")" && pwd)"
AUS_VERZ="$(cd "$(dirname "$AUS")" && pwd)"
[[ "$VERZ" == "$AUS_VERZ" ]] || {
  echo "FEHLER: Ein- und Ausgabe muessen im selben Verzeichnis liegen" >&2; exit 1; }

docker run --rm -v "$VERZ:/work" --entrypoint bash "$IMAGE" -c '
  FF=$(python3 -c "import imageio_ffmpeg;print(imageio_ffmpeg.get_ffmpeg_exe())")
  # -ac 2 erzwingt zwei Kanaele: liegt bereits Stereo an, bleibt es erhalten;
  # ein versehentlich einkanaliges WAV wird sichtbar auf Stereo verdoppelt,
  # statt still als Mono durchzulaufen.
  "$FF" -hide_banner -loglevel error -y \
        -i "/work/'"$(basename "$EIN")"'" \
        -codec:a libmp3lame -b:a '"$BITRATE"'k -ac 2 \
        "/work/'"$(basename "$AUS")"'"
'

# Kanaele der Ausgabe pruefen — eine Umwandlung, die still auf Mono faellt,
# waere genau der Fehler, den dieses Skript beheben soll. Dieselbe Pruefung
# nimmt pruefe_image.sh auf die Antwort des Servers an.
python3 "${HIER}/pruefe_mp3.py" "$AUS"

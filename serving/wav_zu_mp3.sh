#!/usr/bin/env bash
# Wandelt ein erzeugtes WAV in ein MP3 um — und behaelt dabei das Stereobild.
#
# Warum ueberhaupt: sglang-omni kodiert MP3, FLAC, Opus und AAC ausschliesslich
# in Mono. In client/audio.py steht fuer diese Formate stream.layout = "mono"
# fest im Code, mehrkanalige Daten werden davor per audio.mean(...)
# heruntergerechnet; der Kommentar dort nennt die Herkunft ("Streaming chunks
# are mono" — der Pfad stammt aus dem Sprach-Streaming). Nur encode_wav
# behandelt zwei Kanaele korrekt. Bei einem Modell mit 32-kHz-Stereo-Ausgabe
# halbiert der bequeme Weg also die Information.
#
# Deshalb: WAV vom Server holen, hier umkodieren. Das ffmpeg dafuer steckt
# bereits im Serving-Image (imageio-ffmpeg, aarch64, mit libmp3lame) — kein
# zusaetzliches Paket auf dem Host noetig.
#
#   ./wav_zu_mp3.sh lied.wav                # -> lied.mp3, 192 kbit/s
#   ./wav_zu_mp3.sh lied.wav fertig.mp3 320 # eigener Name und eigene Bitrate
set -euo pipefail

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
# waere genau der Fehler, den dieses Skript beheben soll.
python3 - "$AUS" <<'PY'
import struct, sys, pathlib
d = pathlib.Path(sys.argv[1]).read_bytes()
off = 10 + (((d[6] & 0x7F) << 21) | ((d[7] & 0x7F) << 14) | ((d[8] & 0x7F) << 7) | (d[9] & 0x7F)) if d[:3] == b"ID3" else 0
i = d.find(b"\xff", off)
while i >= 0 and i + 3 < len(d):
    if d[i + 1] & 0xE0 == 0xE0:
        h = struct.unpack(">I", d[i:i + 4])[0]
        rate = [44100, 48000, 32000][(h >> 10) & 3]
        modus = ["Stereo", "Joint-Stereo", "Dual-Kanal", "Mono"][(h >> 6) & 3]
        kb = [0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0][(h >> 12) & 15]
        print(f"{sys.argv[1]}: {rate} Hz, {modus}, {kb} kbit/s, {len(d) / 1024:.0f} KB")
        if modus == "Mono":
            sys.exit("FEHLER: Ausgabe ist Mono geworden")
        break
    i = d.find(b"\xff", i + 1)
PY

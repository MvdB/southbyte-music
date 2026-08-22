#!/usr/bin/env python3
"""Prueft, ob eine MP3-Datei stereo ist, und meldet Rate, Modus und Bitrate.

Gemeinsam genutzt von wav_zu_mp3.sh (prueft die eigene Umwandlung) und
pruefe_image.sh (prueft, was der Server ausliefert). Beide brauchen dieselbe
Aussage, und ein stiller Rueckfall auf Mono ist genau der Fehler, der hier
nicht durchrutschen darf — er kostet die Haelfte des Signals, ohne dass eine
Fehlermeldung darauf hinweist.

Gelesen wird der erste Frame-Kopf: ein ID3v2-Vorspann wird uebersprungen, dann
stehen Bitrate, Abtastrate und Kanalmodus in den Bits 12-15, 10-11 und 6-7 des
vier Byte langen Kopfes.

    ./pruefe_mp3.py lied.mp3
"""

import pathlib
import struct
import sys

# Index 3 ist in beiden Tabellen reserviert und darf nicht als Messwert
# durchgehen — ein 'None' hier ist besser als eine erfundene Zahl.
RATEN = [44100, 48000, 32000, None]
MODI = ["Stereo", "Joint-Stereo", "Dual-Kanal", "Mono"]
BITRATEN = [None, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, None]


def erster_frame(daten: bytes) -> int:
    """Versatz des ersten Frame-Kopfes, ID3v2-Vorspann uebersprungen."""
    versatz = 0
    if daten[:3] == b"ID3" and len(daten) >= 10:
        # ID3v2-Groesse steht in vier synchsafe Bytes: je sieben Nutzbits.
        versatz = 10 + (
            ((daten[6] & 0x7F) << 21)
            | ((daten[7] & 0x7F) << 14)
            | ((daten[8] & 0x7F) << 7)
            | (daten[9] & 0x7F)
        )
    i = daten.find(b"\xff", versatz)
    while i >= 0 and i + 3 < len(daten):
        if daten[i + 1] & 0xE0 == 0xE0:
            return i
        i = daten.find(b"\xff", i + 1)
    return -1


def main() -> None:
    if len(sys.argv) != 2:
        sys.exit(f"Aufruf: {sys.argv[0]} <datei.mp3>")
    pfad = pathlib.Path(sys.argv[1])
    daten = pfad.read_bytes()

    i = erster_frame(daten)
    if i < 0:
        sys.exit(f"FEHLER: kein MP3-Frame in {pfad} gefunden ({daten[:12]!r})")

    kopf = struct.unpack(">I", daten[i : i + 4])[0]
    rate = RATEN[(kopf >> 10) & 3]
    modus = MODI[(kopf >> 6) & 3]
    bitrate = BITRATEN[(kopf >> 12) & 15]

    kb = "unbekannt" if bitrate is None else f"{bitrate} kbit/s"
    hz = "reservierte Rate" if rate is None else f"{rate} Hz"
    print(f"  {pfad}: {hz}, {modus}, {kb}, {len(daten) / 1024:.0f} KB")

    if modus == "Mono":
        sys.exit("FEHLER: Ausgabe ist Mono")
    if rate is None:
        sys.exit("FEHLER: reservierte Abtastrate im Frame-Kopf")


if __name__ == "__main__":
    main()

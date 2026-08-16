#!/usr/bin/env python3
"""Objektive Masse fuer den Caption-A/B-Lauf.

Was hier gemessen wird, ist bewusst eng: Dinge, die die Caption ausdruecklich
fordert und die sich ohne Hoeren nachrechnen lassen. Der musikalische Eindruck
bleibt Sache des Ohrs -- dafuer liegen die WAVs daneben.

  * Dauer, Kanaele, Abtastrate       -- lief die Generierung sauber durch
  * Tempo                            -- gefordert sind 150 BPM
  * Stereobreite (Seitenanteil)      -- gefordert ist ein weites Stereobild
  * Dynamikumfang (Crest-Faktor)     -- gefordert ist "loud and compressed"
  * Aufbau (Energie je Viertel)      -- die Langform verspricht einen Bogen
"""

import pathlib
import sys

import numpy as np
import soundfile as sf

ZIEL_BPM = 150.0


def tempo(mono: np.ndarray, sr: int) -> float:
    """Tempo ueber die Autokorrelation der Anschlagshuellkurve.

    Kein librosa auf dieser Maschine, also von Hand: Kurzzeitenergie in
    ~10-ms-Fenstern, positive Differenz als Anschlagsmass, davon die
    Autokorrelation. Das Maximum im Bereich 60-220 BPM ist die Schaetzung.
    """
    hop = max(1, sr // 100)
    rahmen = len(mono) // hop
    energie = np.array(
        [np.sqrt(np.mean(mono[i * hop:(i + 1) * hop] ** 2) + 1e-12) for i in range(rahmen)]
    )
    huelle = np.diff(energie, prepend=energie[0]).clip(min=0)
    huelle -= huelle.mean()
    if not np.any(huelle):
        return float("nan")

    ak = np.correlate(huelle, huelle, mode="full")[len(huelle) - 1:]
    fps = sr / hop
    lo, hi = int(fps * 60 / 220), int(fps * 60 / 60)
    if hi <= lo or hi >= len(ak):
        return float("nan")
    return float(60.0 * fps / (lo + int(np.argmax(ak[lo:hi]))))


def auswerten(pfad: pathlib.Path) -> dict:
    daten, sr = sf.read(str(pfad), always_2d=True)
    mono = daten.mean(axis=1)
    spitze = float(np.max(np.abs(mono))) or 1e-12
    effektiv = float(np.sqrt(np.mean(mono ** 2)))

    if daten.shape[1] == 2:
        seite = daten[:, 0] - daten[:, 1]
        mitte = daten[:, 0] + daten[:, 1]
        breite = float(np.sqrt(np.mean(seite ** 2)) / (np.sqrt(np.mean(mitte ** 2)) + 1e-12))
    else:
        breite = 0.0

    viertel = np.array_split(mono, 4)
    bogen = [float(np.sqrt(np.mean(v ** 2)) / (effektiv + 1e-12)) for v in viertel]

    geschaetzt = tempo(mono, sr)
    return {
        "datei": pfad.name,
        "dauer_s": round(len(mono) / sr, 1),
        "kanaele": daten.shape[1],
        "rate_hz": sr,
        "bpm": round(geschaetzt, 1),
        "bpm_fehler": round(abs(geschaetzt - ZIEL_BPM), 1),
        "breite": round(breite, 3),
        "crest_db": round(20 * np.log10(spitze / (effektiv + 1e-12)), 1),
        "bogen": [round(b, 2) for b in bogen],
    }


def main() -> int:
    hier = pathlib.Path(__file__).resolve().parent
    dateien = sorted(hier.glob("out_*.wav"))
    if not dateien:
        print("Keine WAVs gefunden.")
        return 1

    kopf = f"{'Datei':28} {'Dauer':>6} {'Kan':>4} {'BPM':>6} {'dBPM':>5} {'Breite':>7} {'Crest':>6}  Bogen"
    print(kopf)
    print("-" * len(kopf))
    ergebnisse = []
    for datei in dateien:
        e = auswerten(datei)
        ergebnisse.append(e)
        print(
            f"{e['datei']:28} {e['dauer_s']:>5}s {e['kanaele']:>4} {e['bpm']:>6} "
            f"{e['bpm_fehler']:>5} {e['breite']:>7} {e['crest_db']:>5}  {e['bogen']}"
        )

    print(f"\nZiel: {ZIEL_BPM:.0f} BPM. 'dBPM' ist die Abweichung, kleiner ist besser.")
    for kennung, name in (("a_kurz", "Kurzform"), ("b_lang", "Langform")):
        teil = [e for e in ergebnisse if kennung in e["datei"]]
        if teil:
            mittel = sum(e["bpm_fehler"] for e in teil) / len(teil)
            print(f"  {name:9} mittlere Abweichung {mittel:5.1f} BPM  (n={len(teil)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

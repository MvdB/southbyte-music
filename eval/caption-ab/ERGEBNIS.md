# Caption-A/B: Kurzform gegen Langform

15.08.2026, MiniMax-Music3 auf dem DGX Spark, Adapter auf Port 8011.

## Aufbau

Vier Generierungen, gleiche Lyrics (`lyrics.txt`, gekürztes Beispiel aus der
Weboberfläche), gleiche Framezahl (1750 = 70 s), Seeds 7 und 21.

| Variante | Caption |
|---|---|
| `a_kurz` | `caption_a_kurz.txt` — vierzeilige Kochbuchform, Stand der Weboberfläche |
| `b_lang` | `caption_b_lang.txt` — kanonische Langform, erzeugt mit dem Upstream-Skill `music-caption-rewriter` |

Beide fordern ausdrücklich 150 BPM, E-Moll, Melodic/Symphonic Metal, klare
weibliche Leadstimme, Palm-Mute-Strophe mit Streichern im Refrain.

Nachstellen bei laufendem Adapter auf Port 8011: `./lauf.sh`, danach
`python3 messen.py`. Die vier WAVs liegen nicht im Repository — 36 MB, und
`lauf.sh` erzeugt sie neu. Der Lauf braucht dafür rund 40 Minuten.

## Messwerte

| Datei | BPM | Breite | Crest | Bogen |
|---|---|---|---|---|
| `a_kurz_seed7` | 125,0 | 0,445 | 16,5 dB | 0.67 · 1.24 · 1.15 · 0.83 |
| `a_kurz_seed21` | 92,3 | 0,468 | 17,2 dB | 0.79 · 0.68 · 1.05 · 1.35 |
| `b_lang_seed7` | 87,0 | 0,534 | 16,9 dB | 0.79 · 0.81 · 1.13 · 1.21 |
| `b_lang_seed21` | 76,9 | 0,546 | 16,4 dB | 0.69 · 0.77 · 1.18 · 1.24 |

Rechenzeit je Lauf, alle mit `http=200` und 8 970 008 Byte Ausgabe:

| Lauf | Dauer |
|---|---|
| `a_kurz` Seed 7 | 376 s |
| `a_kurz` Seed 21 | 537 s |
| `b_lang` Seed 7 | 736 s |
| `b_lang` Seed 21 | 532 s |

Die Streuung geht auf den parallel laufenden SB-RISK-Container, nicht auf die
Caption — 1750 Frames sind in allen vier Fällen dieselbe Arbeit.

## Befunde

**Die Langform macht den Aufbau reproduzierbar.** Mittlere Abweichung der
Energiebögen zwischen den beiden Seeds: 0,055 bei der Langform, 0,325 bei der
Kurzform. Die Kurzform lieferte bei Seed 7 und Seed 21 gegenläufige Verläufe,
die Langform beide Male denselben Aufbau.

**Die Langform steuert das Klangbild.** Stereobreite 0,534/0,546 gegen
0,445/0,468 — kein Überlappen zwischen den Varianten. Hartes Panning und die
Platzierung der Streicher hinter den Gitarren waren in der Langform ausdrücklich
verlangt.

**Lautheit und Dynamik unterscheiden sich nicht** (Crest 16,4–17,2 dB).

**Das Tempo verfehlen beide.** Bei 150 BPM liegt die Autokorrelation der
Anschlagshüllkurve in allen vier Dateien bei 0,017–0,081, beim jeweils gefundenen
Tempo dagegen bei 0,115–0,210. Ob 87 oder 174 BPM geliefert wurde, lässt sich mit
diesem Verfahren nicht auf den Faktor zwei genau entscheiden — 150 ist es nicht.

## Zum Verfahren

Kein librosa auf der Maschine, der Temposchätzer in `messen.py` ist eine
Autokorrelation über die Anschlagshüllkurve. Gegen synthetische Klickspuren ist
er exakt (150 → 150,0; 125 → 125,0; 92 → 92,3). Seine eine bekannte Schwäche:
Bei dominantem Backbeat rastet er auf die halbe Rate ein (150 mit betonter 2 und
4 → 75,0). Deshalb die Zurückhaltung beim absoluten Tempowert oben.

Der Höreindruck bestätigte die Größenordnung der Tempowerte.

## Grenzen

Ein Genre, ein Lyrics-Satz, zwei Seeds je Variante. Verglichen wurde die *Form*
der Caption — kurz gegen lang. **Nicht** verglichen wurde, ob die
Vorlagenbibliothek des Upstream-Skills gegenüber einer frei geschriebenen
Langform etwas beiträgt; dafür bräuchte es einen dritten Arm.

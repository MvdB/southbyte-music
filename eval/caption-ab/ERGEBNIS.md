# Caption-A/B: Kurzform, Langform, Vorlagenbibliothek

MiniMax-Music3 auf dem DGX Spark, Adapter auf Port 8011. Zwei Läufe an zwei
Tagen — **und die beiden sind nicht ohne Weiteres vergleichbar**, siehe
*Determinismus und Serverstand*.

## Aufbau

Gleiche Lyrics (`lyrics.txt`, gekürztes Beispiel aus der Weboberfläche), gleiche
Framezahl (1750 = 70 s), Seeds 7 und 21. Nur die Caption wechselt.

| Variante | Caption | Gelaufen am |
|---|---|---|
| `a_kurz` | `caption_a_kurz.txt` — vierzeilige Kochbuchform, damaliger Stand der Weboberfläche | 15.08.2026 |
| `b_lang` | `caption_b_lang.txt` — kanonische Langform, frei geschrieben nach dem Schema des Upstream-Skills | 15.08.2026 |
| `c_biblio` | `caption_c_biblio.txt` — Langform, abgeleitet aus der **Vorlagenbibliothek** des Skills | 16.08.2026, Serverstand `0.1.1` |

Alle drei fordern ausdrücklich 150 BPM, E-Moll, Melodic/Symphonic Metal, klare
weibliche Leadstimme, Palm-Mute-Strophe mit Streichern im Refrain.

`c_biblio` ist nach dem Verfahren des `musik-caption`-Skills gebaut, nicht frei
formuliert: Genre-Router → Familie `metal-heavy-rock` → Foundation
`symphonic-metal-hard-rock_0001` (trifft Genre *und* weibliche Lead), dazu
`symphonic-metal-melodic-metalcore_0001` als Modifier allein für den treibenden
Groove, den die 95-BPM-Foundation nicht hergibt. Deren zweite Männerstimme mit
Growls bleibt draußen — die ausdrückliche Vorgabe schlägt die
Vorlageneigenschaft. Satzähnlichkeit zu beiden Vorlagen: 0 bei Schwelle 0,6 und
0,55.

Nachstellen bei laufendem Adapter auf Port 8011: `./lauf.sh`, danach
`python3 messen.py`. Einzelne Arme mit `./lauf.sh c_biblio`, ein Kontrollauf ohne
Überschreiben mit `SEEDS=7 SUFFIX=_kontrolle ./lauf.sh b_lang`. Die WAVs liegen
nicht im Repository — 9 MB je Stück, und `lauf.sh` erzeugt sie neu. Je
Generierung rund sechs bis zwölf Minuten.

## Messwerte

| Datei | BPM | Breite | Crest | Bogen |
|---|---|---|---|---|
| `a_kurz_seed7` | 125,0 | 0,445 | 16,5 dB | 0.67 · 1.24 · 1.15 · 0.83 |
| `a_kurz_seed21` | 92,3 | 0,468 | 17,2 dB | 0.79 · 0.68 · 1.05 · 1.35 |
| `b_lang_seed7` | 87,0 | 0,534 | 16,9 dB | 0.79 · 0.81 · 1.13 · 1.21 |
| `b_lang_seed21` | 76,9 | 0,546 | 16,4 dB | 0.69 · 0.77 · 1.18 · 1.24 |
| `c_biblio_seed7` | 120,0 | 0,473 | 17,5 dB | 0.78 · 0.88 · 1.16 · 1.13 |
| `c_biblio_seed21` | 88,2 | 0,582 | 17,3 dB | 0.74 · 0.74 · 1.13 · 1.28 |
| `b_lang_seed7_kontrolle` | 109,1 | 0,528 | 17,0 dB | 0.96 · 0.41 · 1.08 · 1.32 |
| `b_lang_seed7_kontrolle2` | 109,1 | 0,528 | 17,0 dB | 0.96 · 0.41 · 1.08 · 1.32 |

Je Variante, wie `messen.py` es ausgibt:

| Variante | n | dBPM | Breite | Crest | dBogen |
|---|---|---|---|---|---|
| `a_kurz` | 2 | 41,4 | 0,457 | 16,9 | **0,325** |
| `b_lang` | 2 | 68,0 | 0,540 | 16,6 | **0,055** |
| `c_biblio` | 2 | 45,9 | 0,527 | 17,4 | **0,090** |

`dBogen` ist die mittlere Abweichung der Energiebögen zwischen den beiden Seeds
einer Variante. Klein heißt: Die Caption bestimmt die Form des Stücks, der Seed
nur noch Melodie und Klangfarbe.

Rechenzeit je Lauf, alle mit `http=200` und 8 970 008 Byte Ausgabe:

| Lauf | Dauer |
|---|---|
| `a_kurz` Seed 7 / 21 | 376 s · 537 s |
| `b_lang` Seed 7 / 21 | 736 s · 532 s |
| `c_biblio` Seed 7 / 21 | 370 s · 372 s |
| `b_lang` Seed 7, beide Kontrollläufe | 370 s · 371 s |

Die Streuung am 15.08. geht auf eine parallel laufende zweite Last auf derselben
GPU, nicht auf die Caption — 1750 Frames sind in allen Fällen dieselbe Arbeit. Am
16.08. lief die Maschine allein, und prompt liegen alle vier Läufe innerhalb von
zwei Sekunden.

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
Der dritte Arm verfehlt es genauso.

### Was der dritte Arm zeigt — und was nicht

**Er ist gemessen, der Vergleich ist es nicht.** `c_biblio` steht bei dBogen
0,090 und mittlerer Breite 0,527, das sind saubere Werte innerhalb von `0.1.1`.
Sie *neben* die 0,055 und 0,540 von `b_lang` zu stellen wäre aber ein Vergleich
über die Versionsgrenze, und genau der ist oben als unzulässig belegt. Ob die
Vorlagenbibliothek gegenüber einer frei geschriebenen Langform etwas beiträgt,
ist damit **weiterhin offen** — der Arm existiert, sein Gegenüber fehlt.

Was innerhalb von `0.1.1` steht und keine Versionsgrenze überschreitet: `c_biblio`
schwankt in der Stereobreite deutlich zwischen den Seeds (0,473 gegen 0,582),
während `b_lang` das am 15.08. nicht tat (0,534 gegen 0,546). Ein Hinweis, mehr
nicht — die beiden Zahlenpaare stammen wieder von verschiedenen Ständen.

## Determinismus und Serverstand

Der dritte Arm lief auf einem anderen Serverstand als die ersten beiden. Ob
darüber hinweg überhaupt verglichen werden darf, ist keine Geschmacksfrage,
also wurde es gemessen: `b_lang` Seed 7 noch einmal, mit unveränderter Caption,
unverändertem Lyrics-Text, gleichem Seed und gleicher Framezahl.

**Er reproduziert die Werte vom 15.08. nicht.** Bogen `0.79 · 0.81 · 1.13 · 1.21`
damals gegen `0.96 · 0.41 · 1.08 · 1.32` heute — mittlere Abweichung **0,18**,
also größer als der Unterschied zwischen den Seeds, der oben als Befund steht.
Stereobreite und Crest blieben dagegen fast gleich (0,534 → 0,528; 16,9 → 17,0).

Dafür gab es zwei Erklärungen, und ein zweiter Kontrollauf trennt sie: Die
beiden Wiederholungen auf dem heutigen Stand sind **auf jede ausgegebene Stelle
identisch**. Also **Versionsdrift zwischen den Serverständen, kein
Nichtdeterminismus**. Bei festem Seed liefert derselbe Stand denselben Ton.

Zwei Folgerungen:

1. **Der Befund von oben steht.** Alle vier Läufe vom 15.08. lagen auf demselben
   Stand; 0,055 gegen 0,325 ist ein Vergleich innerhalb einer Version und bleibt
   gültig.
2. **`c_biblio` ist mit `a_kurz` und `b_lang` noch nicht vergleichbar.** Dazu
   müssten die beiden auf `0.1.1` neu laufen — drei Generierungen, rund zwanzig
   Minuten. Steht aus.

Wer künftig Captions vergleicht: **Arme desselben Vergleichs gehören auf
denselben Serverstand.** Ein Kontrollauf kostet zehn Minuten und ist der
einzige Weg, das überhaupt zu bemerken.

## Zum Verfahren

Kein librosa auf der Maschine, der Temposchätzer in `messen.py` ist eine
Autokorrelation über die Anschlagshüllkurve. Gegen synthetische Klickspuren ist
er exakt (150 → 150,0; 125 → 125,0; 92 → 92,3). Seine eine bekannte Schwäche:
Bei dominantem Backbeat rastet er auf die halbe Rate ein (150 mit betonter 2 und
4 → 75,0). Deshalb die Zurückhaltung beim absoluten Tempowert oben.

Der Höreindruck bestätigte die Größenordnung der Tempowerte.

## Grenzen

Ein Genre, ein Lyrics-Satz, zwei Seeds je Variante. Belegt ist damit genau ein
Vergleich: die *Form* der Caption, kurz gegen lang, innerhalb des Serverstands
vom 15.08.2026.

**Offen bleibt der Beitrag der Vorlagenbibliothek.** Der dritte Arm ist
geschrieben und gerechnet, aber `a_kurz` und `b_lang` müssen auf `0.1.1`
nachlaufen, bevor die drei nebeneinander stehen dürfen — drei Generierungen,
rund zwanzig Minuten.

**Offen bleibt außerdem das Ohr.** Gemessen sind Tempo, Breite, Crest und
Energiebogen. Ob eine Variante *besser klingt*, sagt keine dieser Zahlen; die
WAVs liegen daneben.

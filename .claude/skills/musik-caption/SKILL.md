---
name: musik-caption
description: Schreibt oder überarbeitet die Caption für MiniMax-Music3 — den Strukturtext, der als `instructions` neben die Lyrics geht. Verwenden, sobald für southbyte-music ein Klangbild beschrieben, ein bestehender Prompt verbessert, ein Genre getroffen oder ein Fehlversuch analysiert werden soll. Kennt beide Formen des Schemas, die harten Grenzen des Modells und die auf dem DGX Spark gemessenen Eigenheiten. Bringt 1000 Referenz-Captions über 18 Stilfamilien mit, erschlossen über einen Genre-Router — auch für Genres, die man nicht im Ohr hat.
---

# Caption für MiniMax-Music3

Die Caption ist der Regler für alles außer dem Text. Sie geht als `instructions`
an `/v1/audio/speech`, die Lyrics als `input`. Was die Caption nicht sagt,
entscheidet das Modell selbst — und meistens anders als gedacht.

## Harte Grenzen

Diese Zahlen stehen fest und sind auf der Maschine gemessen, nicht geschätzt.
Belege im README unter *Measured on the DGX Spark*.

| | |
|---|---|
| Prompt-Kontext | **5000 Token** für Lyrics *und* Caption zusammen. Eine 450-Wort-Caption sind ~600 Token — Platz ist da, aber er ist nicht unendlich |
| Länge | 25 fps, maximal **7500 Frames** = 5:00. Darüber verlässt man den trainierten Bereich |
| Frames aus Text | ~**1,62 gesungene Silben pro Sekunde**. Silben zählen, durch 1,62 teilen, 20 % Reserve draufrechnen |
| Early Stop | Großzügig aufrunden ist gratis: Das Modell hört von selbst auf und meldet `finish_reason=stop` |
| Rechenzeit | ~5–6× der Spielzeit; die Oberfläche rechnet mit 22 s Fixkosten plus 0,211 s je Frame |
| Ausgabe | WAV ist 32 kHz **stereo**. MP3 ist **mono** — eine Grenze von sglang-omni, nicht des Modells. Für Stereo-MP3 hinterher `serving/wav_zu_mp3.sh` |

### BPM ist ein Wunsch, keine Vorgabe

Vier Läufe mit ausdrücklich geforderten 150 BPM — zweimal `Basic Attributes:
bpm is 150`, zweimal die Kurzform mit derselben Zahl — ergaben in **keinem**
Fall einen nennenswerten Puls bei 150. Die Autokorrelation der Anschlagshüllkurve
liegt dort bei 0,017–0,081, beim jeweils tatsächlich gefundenen Tempo dagegen bei
0,115–0,210. Ob das gelieferte Tempo dann 87 oder 174 BPM ist, lässt sich mit
diesem Verfahren nicht auf den Faktor zwei genau sagen — 150 ist es nicht.

Die Zahl trotzdem hinschreiben: Sie kostet nichts und wirkt als Stilsignal
mit. Aber **nicht darauf bauen**, und wenn das Tempo wirklich zählt, hinterher
nachmessen statt der Caption glauben.

Belegt an einem Genre und einem Lyrics-Satz, vier Läufe. Für die Aussage „hält
Tempo generell nicht ein" bräuchte es mehrere Genres und Zieltempi. Messwerte und
Rezept unter [`eval/caption-ab/`](../../../eval/caption-ab/ERGEBNIS.md).

## Die Caption ist englisch

Das ist keine Stilfrage. Eine deutsche Stilbeschreibung zog das Ergebnis hörbar
Richtung deutschsprachiger Popmusik — *„Melodischer Metal, 150 BPM, verzerrte
Gitarrenwand"* klang näher an Neuer Deutscher Welle als an Metal. Dieselben
Lyrics mit englischer Caption trafen das Genre deutlich besser.

**Lyrics dürfen jede Sprache haben.** Bei deutschen zwei beobachtete Eigenheiten:

- **Umlaute umschreiben**, sonst verschluckt das Modell sie. Im Textfeld sieht
  das schief aus, gesungen ist es das kleinere Übel.
- **Englische Wörter in deutschen Zeilen sind uneinheitlich.** Ein durchgehend
  großgeschriebenes markenartiges Wort kam deutsch ausgesprochen heraus.
  Englische **Eigennamen** dagegen wurden in sonst deutschen Zeilen bisher
  ausnahmslos richtig gesungen — sie also nicht vorsorglich lautschriftlich
  umschreiben, das verschlimmert es nur.

Das sind eine Handvoll Stücke, keine Untersuchung. Wo ein bestimmtes Wort zählt,
einmal hinhören statt einer der beiden Regeln zu glauben.

## Das Schema

Zwei Formen, dieselbe Struktur. Die Kurzform ist die Kurzfassung der Langform,
nicht etwas anderes.

**Im Zweifel die Langform.** Ein A/B-Lauf über vier Generierungen — beide Formen,
je zwei Seeds, gleiche Lyrics, gleiche Framezahl — hat sie an zwei Stellen vorn
gesehen und an keiner hinten:

- **Der Aufbau wird reproduzierbar.** Die Energieverläufe der Langform waren über
  beide Seeds fast deckungsgleich, die der Kurzform liefen gegeneinander (mittlere
  Abweichung 0,055 gegen 0,325). Wer das Arrangement Abschnitt für Abschnitt
  beschreibt, überlässt dem Seed noch Melodie und Klangfarbe, aber nicht mehr die
  Form des Stücks.
- **Das Klangbild folgt der Ansage.** Ausdrücklich verlangtes hartes Panning und
  Streicher hinter den Gitarren schlugen als messbar größere Stereobreite durch
  (0,54 gegen 0,46), ohne Überlappung zwischen den Varianten.
- Lautheit und Dynamik unterschieden sich nicht, das Tempo bei beiden gleich
  wenig — siehe oben.

Die Kurzform bleibt richtig für schnelle Versuche, wenn nur das Genre sitzen soll.
Aufbau, Messwerte und Grenzen des Laufs stehen in
[`eval/caption-ab/ERGEBNIS.md`](../../../eval/caption-ab/ERGEBNIS.md), die beiden
verglichenen Captions daneben.

**Nicht entschieden** ist, ob die Vorlagenbibliothek gegenüber einer frei
geschriebenen Langform etwas beiträgt. Ein dritter Arm dazu liegt inzwischen in
`eval/caption-ab/`, er lief aber auf einem neueren Serverstand — und der ändert
das Ergebnis bei festem Seed nachweislich. Bis die ersten beiden Arme dort
nachgelaufen sind, sagt dieser Skill über die Bibliothek nichts aus.

### Kurzform — vier Zeilen

Der dokumentierte Stand aus dem Kochbuch, und was in der Weboberfläche steht.
Für schnelle Versuche und wenn nur das Genre sitzen soll.

```
Basic Attributes: bpm is 150, key is E minor, Melodic Heavy Metal / Symphonic Metal.
Emotional Progression: driving and defiant from the first bar, palm-muted verse riff building into a soaring anthemic chorus.
Sonics: heavily distorted rhythm guitars, double kick drums, orchestral string pad under the chorus, loud and tightly compressed.
Vocals: clean powerful female lead, layered harmonies in the chorus.
```

### Langform — drei Überschriften mit benannten Feldern

Das vollständige Schema. Es steht nicht im Kochbuch, sondern lässt sich aus den
Referenz-Captions des Herstellers ablesen.

```
Global Metadata
  Basic Attributes:                bpm, key, scale, Genre / Subgenre
  Global Emotional Progression:    der Bogen über das ganze Stück
  Application Scenarios & Imagery: wofür, welches Bild
  Sonics & Production Profile:     Bühnenbreite, Frequenzbild, Dynamik

Vocal Details
  Vocal Gender & Timbre:           Besetzung, Stimmfarbe, Lage
  Vocal Style:                     Vortrag je Abschnitt
  Harmony/Backing Vocals:          wo Sätze einsetzen und wo nicht
  Vocal FX:                        Hall, Delay, Sättigung — zurückhaltend

Arrangement
  Instrument Lifecycle:            Primär/Sekundär, wer wann einsetzt und geht
  Groove & Foundation Progression: Rhythmusgruppe über die Abschnitte
  Embellishments, Textures, FX:    Übergänge, Riser, Raum
```

Bei Instrumentalstücken tritt an die Stelle der Gesangsangaben die Feststellung,
dass es instrumental ist, plus das Instrument, das die Melodie führt.

## Referenzen finden

Im Verzeichnis liegen 1000 vollständige Referenz-Captions des Herstellers, sortiert
über 18 Stilfamilien. Sie sind der schnellste Weg zu einem Genre, das man nicht im
Ohr hat — aber nur, wenn man sie **nicht** durchsucht.

**Nie alle Vorlagen scannen, keine Dateinamen durchgrepen, keine Datenbank bauen.**
Der Korpus ist auf schrittweises Aufdecken ausgelegt; wer ihn breit einliest,
verbrennt Kontext und trifft es trotzdem nicht besser. Drei Schritte:

1. **[`references/genre-router.md`](references/genre-router.md) lesen.** Er ordnet die
   Absicht einer Familie zu. Genre, Groove, Instrumentierung und kultureller Kontext
   sind stärkere Signale als Adjektive: `ballad`, `emotional`, `epic`, `modern`,
   `dark` und `cinematic` gelten als Modifikatoren, nicht als Genre. Der Router führt
   auch chinesische Bezeichnungen (华语流行, 国风流行, 氛围 R&B) auf ihre Familie zurück.
2. **Einen Familienindex lesen**, bei ausdrücklicher Fusion einen zweiten. Nie mehr
   als zwei. Der Index trägt Karten mit Stil, Tempo und Tonart, Stimmungsbogen,
   Stimmlage, Instrumentierung und dem Pfad zur vollständigen Vorlage.
3. **Höchstens drei Vorlagen öffnen**, und zwar mit verteilten Rollen:
   - **Foundation** — nächste Verwandte bei Identität, Groove und Songsprache.
   - **Modifier** — nur für die eine Dimension, die sie beisteuert: ein zweites
     Genre, eine Stimmfarbe, eine kulturelle Färbung, ein Produktionscharakter.
   - **Arrangement** — nur für Ablauflogik: Abschnittsentwicklung, Energiebogen,
     Übergänge, Instrumentenlebenslauf.

   Bei einfachen Anfragen genügen eine oder zwei. Keine schwache Vorlage nehmen,
   nur um auf drei zu kommen.

**Aus einer Vorlage wird abgeleitet, nicht abgeschrieben.** Nicht ihr BPM, nicht
ihre Tonart, nicht ihre Besetzung, nicht ihre Abschnittsfolge und schon gar keine
Sätze. Sie zeigt, wie ein Genre klingt und wie ein Arrangement atmet — den Rest
liefert die Absicht des Nutzers. Vorlagenkennungen, Routing-Entscheidungen und die
Auswahl gehören nicht in die Antwort, außer sie werden ausdrücklich verlangt.

Welche Familien es gibt und wie sie sich abgrenzen, steht im Router; Herkunft und
Lizenz des Korpus in [`HERKUNFT.md`](HERKUNFT.md).

## Vorgehen

1. **Absicht sammeln.** Genre, Stimmung, Tempo, Tonart, Besetzung, Instrumente,
   Produktionscharakter, ausdrückliche Ausschlüsse. Jede Angabe innerlich als
   *ausdrücklich*, *aus einem Lyrics-Tag*, *erschlossen* oder *offen* führen — was
   offen ist, bleibt offen.
2. **Referenzen holen**, wenn das Genre nicht selbstverständlich ist: Router,
   Familienindex, bis zu drei Vorlagen (siehe oben). Bei einem vertrauten Genre und
   klarer Absicht ist das übersprungen — der Umweg lohnt nicht immer.
3. **Abschnitte aus den Lyrics übernehmen.** Die eckigen Klammern `[Intro]`,
   `[Verse]`, `[Pre-Chorus]`, `[Chorus]`, `[Bridge]`, `[Outro]` sind
   Anweisungen. Das Arrangement folgt genau diesen Abschnitten — keine erfinden,
   keine übergehen.
4. **Nichts erfinden, was nicht gefordert ist.** Kein exaktes BPM, keine Tonart,
   kein Stimmgeschlecht, wenn die Vorgabe es offen lässt. Eine Bandbreite oder
   eine qualitative Angabe ist ehrlicher und schadet weniger als eine geratene
   Zahl. Das gilt besonders gegenüber einer Vorlage: Ihre Zahlen gehören ihr.
5. **Ausdrückliche Vorgaben schlagen alles.** Ein gefordertes Instrumentalstück
   bleibt instrumental. Ein gefordertes Stimmgeschlecht wird nicht gedreht. Ein
   Ausschluss bleibt ein Ausschluss. Bei Widerspruch gilt diese Rangfolge:

   1. ausdrückliche Forderungen und Ausschlüsse des Nutzers
   2. Anweisungen aus einem Lyrics-Tag — aber nur innerhalb ihres Abschnitts
   3. was die Beschreibung stark nahelegt
   4. Eigenschaften der gewählten Referenzen
   5. konservative musikalische Voreinstellungen

   Ein Abschnitts-Tag darf das Arrangement lokal ändern, ohne das Genre des
   Stücks zu kippen. Widersprechen sich zwei ausdrückliche Angaben, gilt die
   speziellere und spätere, solange die Absicht klar bleibt — sonst der kleinste
   musikalisch stimmige Kompromiss.
6. **Konkrete musikalische Veränderungen statt Vokabelhaufen.** „Palm-Mute
   öffnet sich zu offenen Powerchords, Streicher steigen darunter" ist
   brauchbar; „episch, druckvoll, modern" ist es nicht.
7. **Lyrics nie wiederholen.** Nicht zitieren, nicht zusammenfassen, nicht
   umschreiben. Sie stehen schon im `input`-Feld. Aus dem Text darf die
   Gefühlslage abgelesen werden, mehr nicht.

## Prüfen, bevor es rausgeht

- Caption englisch, Lyrics beliebig
- jede ausdrückliche Vorgabe steht drin und ist nicht gedreht
- jeder Abschnittsmarker aus den Lyrics kommt im Arrangement vor
- kein Lyrics-Zitat, kein Titel, keine Vorlagenkennung
- Instrumente setzen nachvollziehbar ein, verändern sich und gehen wieder
- kein erfundenes BPM, keine erfundene Tonart
- kein Satz und keine vollständige Struktur aus einer Vorlage übernommen
- Frames passen zur Silbenzahl, mit Reserve

## Ausprobieren

```bash
cd serving && ./run_music.sh          # Port 8011, bereit nach ~160 s
curl http://127.0.0.1:8011/v1/audio/speech \
  -H 'Content-Type: application/json' \
  -d @anfrage.json -o lied.wav
```

`anfrage.json` trägt `input` (Lyrics), `instructions` (Caption), `seed` und
`max_new_tokens` (Frames). Wie sie zusammengesetzt wird, zeigt
[`eval/caption-ab/lauf.sh`](../../../eval/caption-ab/lauf.sh).

Gleicher Seed, gleiche Frames, gleiche Lyrics — nur dann sagt ein Vergleich
zweier Captions etwas aus. Objektive Maße dazu liefert
[`eval/caption-ab/messen.py`](../../../eval/caption-ab/messen.py): Tempo,
Stereobreite, Crest-Faktor und den Energiebogen über vier Viertel. Der
musikalische Eindruck bleibt Sache des Ohrs.

## Herkunft

Dieser Skill ist gemischt, und die Trennung ist scharf:

- **`SKILL.md` ist eigener Text.** Die gemessenen Grenzen, der BPM-Befund, die
  deutschen Lyrics-Eigenheiten und der Langform-A/B stehen so nur hier — der
  Upstream kennt weder diese Maschine noch dieses Serving. Übernommen sind die
  Feldnamen des Caption-Schemas, die Reihenfolge der Abschnitte und das Verfahren
  zum Auffinden von Referenzen.
- **`references/`, `templates/` und `LICENSE` sind unverändert übernommen** aus
  [`music-caption-rewriter`](https://github.com/MiniMax-AI/MiniMax-Music3/tree/main/skills/music-caption-rewriter)
  von MiniMax-AI, Stand 15.08.2026, Commit `9456550`. Sie stehen unter der
  *MiniMax-Music3 Community License*, die Weitergabe erlaubt, solange der
  Lizenztext mitreist.

Was das im Einzelnen bedeutet — auch die kommerziellen Auflagen — steht in
[`HERKUNFT.md`](HERKUNFT.md). Kurz: **in `references/` und `templates/` wird nicht
editiert.** Aktualisiert wird durch Neukopieren aus dem Upstream.

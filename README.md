# southbyte-music

Text-zu-Musik auf dem **NVIDIA DGX Spark** (GB10 SoC, sm_120, 128 GB Unified
Memory, aarch64) — Serving-Adapter plus schlanke Weboberfläche zum Erzeugen
ganzer Stücke aus Text und Beschreibung.

> **Proof of Concept — kein Produkt.** Dieses Repo zeigt, dass sich
> MiniMax-Music3 auf einem DGX Spark betreiben lässt und wie. Es ist keine
> Anwendung mit zugesicherter Verfügbarkeit, Eignung oder Ergebnisqualität, es
> gibt keinen Support und keine Roadmap. Wer es nachbaut, sollte damit rechnen,
> selbst Hand anlegen zu müssen.
>
> **Stand 2026-08-14:** läuft. Server bereit nach 160 s, Musik erzeugt und
> geprüft. Alle Zahlen unten sind gemessen, nicht geschätzt.

## Voraussetzungen

| | |
|---|---|
| Hardware | NVIDIA DGX Spark (GB10, sm_120, 128 GB Unified Memory, aarch64). Anderes CUDA-Gerät mit ≥ 60 GB sollte gehen, ist aber ungetestet |
| Modell | [MiniMaxAI/MiniMax-Music3](https://huggingface.co/MiniMaxAI/MiniMax-Music3), rund 54 GB auf der Platte |
| Laufzeit | Docker mit GPU-Zugriff |
| Ablage | Modelle unter `~/hf_models/<owner>--<model>` (überschreibbar per `HF_MODELS_DIR`) |

Das Modell wird **read-only** eingebunden; das Repo schreibt nichts in den
Modellspeicher.

```bash
# Modell holen (Beispiel)
hf download MiniMaxAI/MiniMax-Music3 --local-dir ~/hf_models/MiniMaxAI--MiniMax-Music3

# Image bauen (rund 2 Minuten, das Basisimage bringt den Stack mit)
docker build -t spark-sglang-omni:v1 -f serving/Dockerfile.music serving/
```

## Modell

[MiniMaxAI/MiniMax-Music3](https://huggingface.co/MiniMaxAI/MiniMax-Music3) —
hybrides System aus einem globalen 8B-LLM (Qwen3-8B-Basis) für die Struktur,
einem lokalen 0,6B-LLM für akustische Details, 2,4B Flow-Matching und einem
123M Flow-VAE-Decoder. Rund 47 GB Gewichte.

| Eigenschaft | Wert |
|---|---|
| Eingabe | Lyrics mit Abschnitts-Tags + Beschreibung (Genre, BPM, Tonart, Stimmung) |
| Ausgabe | 32 kHz, 16 bit, Stereo-WAV |
| Maximale Länge | **5 Minuten** = 7500 Frames bei 25 fps — dafür ist das Modell gebaut und trainiert. Die technische Schranke unter „Limitations“ liegt höher (9000 Frames = 6:00), aber darüber verlässt man den trainierten Bereich |
| Kontext | 5000 Tokens Prompt |
| Streaming | nicht unterstützt |

## Gemessen auf dem DGX Spark (GB10, 2026-08-14)

| | |
|---|---|
| Serverstart | 160 s |
| Rechenzeit | rund **5–6× der Spieldauer**; vier Messpunkte: 250/750/1500/3839 Frames → 85/157/356/831 s |
| Frames aus Text | rund **1,62 gesungene Silben je Sekunde** — der Beispieltext (22 Zeilen, 234 Silben) landet mit 20 % Reserve bei 4350 Frames ≈ 2:54 |
| Vorzeitiges Ende | verifiziert: bei angeforderten 4000 Frames meldete der Server `AR done frames=3839 finish_reason=stop` — großzügig aufrunden kostet nichts |
| Attention-Backend | `torch_sdpa` — flash-attn wird nicht gebraucht |
| Ausgabe WAV | 32 kHz, **Stereo**, 16 bit |
| Ausgabe MP3 | 32 kHz, **Mono**, 40 kbit/s |

Die Oberfläche rechnet mit **22 s Grundlast plus 0,211 s je Frame** und
kennzeichnet das Ergebnis als Schätzung. Eine erste Fassung war nur aus den
beiden kurzen Läufen (250 und 750 Frames) abgeleitet und lag bei 1500 Frames um
ein Viertel zu niedrig — kurze Läufe taugen nicht zur Hochrechnung auf lange.
Erst der vierte Messpunkt bei 3839 Frames hat die Gerade gerade gerückt.

Die Länge ist bei **7500 Frames** gedeckelt. Das `max`-Attribut hält nur die
Pfeiltasten auf, getippt werden darf alles — deshalb deckelt die Oberfläche vor
dem Absenden noch einmal hart. Braucht der Text mehr als 5:00, sagt sie das und
verlangt Kürzen, statt still abzuschneiden.

**MP3 ist Mono — und das ist eine Einschränkung von sglang-omni, keine des
Modells.** In `sglang_omni/client/audio.py` steht für alle komprimierten Formate
`stream.layout = "mono"` fest im Code, und mehrkanalige Daten werden davor per
`audio.mean(...)` heruntergerechnet. Der Kommentar dort nennt den Grund:
*"Streaming chunks are mono"* — der Pfad stammt aus dem Sprach-Streaming, wo Mono
die Norm ist. `encode_wav` behandelt zwei Kanäle dagegen korrekt.

Bei einem Modell, dessen Ausgabe 32 kHz **Stereo** ist, halbiert der bequemste
Ausgabeweg also die Information. Die Oberfläche hat deshalb **WAV als Vorgabe**;
MP3 bleibt wählbar, mit dem Hinweis daneben.

Für ein **Stereo-MP3** wandelt `serving/wav_zu_mp3.sh` ein erzeugtes WAV um. Das
ffmpeg dafür steckt bereits im Serving-Image, auf dem Host muss nichts
installiert werden:

```bash
serving/wav_zu_mp3.sh lied.wav              # -> lied.mp3, 192 kbit/s, Stereo
serving/wav_zu_mp3.sh lied.wav fertig.mp3 320
```

Das Skript prüft die Ausgabe und bricht ab, falls sie doch einkanalig würde.
Ein Entwurf für einen Fehlerbericht an das Projekt liegt unter
[`docs/upstream-issue-mono.md`](docs/upstream-issue-mono.md).

**Die Caption gehört auf Englisch.** Sämtliche Beispiele des Herstellers sind
englisch. Eine deutsche Stilbeschreibung zog das Ergebnis hörbar in Richtung
deutschsprachiger Popmusik — aus „Melodischer Metal, 150 BPM, verzerrte
Gitarrenwand" wurde etwas, das eher an Neue Deutsche Welle erinnerte. Dieselben
Lyrics mit englischer Caption im Format des Kochbuchs trafen das Genre deutlich
besser. **Die Lyrics dürfen deutsch bleiben**, nur die Beschreibung nicht.

Format laut Kochbuch, und je konkreter desto besser:

```
Basic Attributes: bpm is 150, key is E minor, Melodic Heavy Metal.
Emotional Progression: driving and defiant from the first bar, building into a
soaring anthemic chorus.
Sonics: heavily distorted rhythm guitars, double kick drums, orchestral string
pad under the chorus, loud and tightly compressed.
Vocals: clean powerful female lead, layered harmonies in the chorus.
```

## Warum SGLang-Omni und kein eigener Adapter

MiniMax-Music3 wird vom Hersteller über SGLang-Omni bedient und bringt dort
`/v1/audio/speech` **nativ** mit — dieselbe OpenAI-kompatible Schnittstelle, die
auch die TTS-Adapter der Familie sprechen. Damit braucht eine spätere Evaluation
nur eine andere URL, und wir schreiben keinen Adapter, den es schon gibt.

Das ist dieselbe Konstellation wie bei Voxtral-TTS in
[southbyte-tts](https://github.com/MvdB/southbyte-tts): auch dort liefert
vLLM-Omni den Endpoint nativ, statt dass ein eigener Server davorgesetzt wird.

**Warum nicht ComfyUI** (obwohl es ein offizielles Workflow-Template gibt):
ComfyUI verlangt eigene, umgepackte Gewichtsdateien
(`minimax_music3_dit_fp16.safetensors`, `…_text_encoder_pruned_int8_convrot…`,
`…_dav.safetensors`) in `models/diffusion_models/`, `models/text_encoders/` und
`models/vae/`. Das wäre dasselbe Modell ein zweites Mal auf der Platte, in einem
anderen Format und außerhalb von `~/hf_models` — also außerhalb der Konvention,
dass jeder Stack denselben Modellspeicher read-only einbindet. Dazu lädt ComfyUI
das Modell selbst, was mit dem Serving-Weg kollidiert, und ein Headless-/API-
Betrieb ist nicht dokumentiert. Als Node-Editor zum Parameter-Ausprobieren bleibt
es nützlich, als Fundament für eine Oberfläche zum Musikmachen nicht.

## Stolpersteine, die Zeit gekostet haben

**`sgl-omni` steckt nicht im Standard-Image.** In `lmsysorg/sglang:dev` finden
sich nur `sglang`, `sglang-kernel` und `sglang-router`. SGLang-Omni ist ein
eigenes Projekt, so wie vllm-omni neben vllm steht.

**Das PyPI-Release kennt MiniMax-Music3 nicht.** Version 0.1.1 bricht beim Start
ab mit `Config for MiniMaxMusic3ForConditionalGeneration not found in the
pipeline config registry`. Unterstützt wird es erst seit Commit `05e268a4` vom
2026-08-13 — daher die Installation aus `git main`.

**`flashinfer-cubin` muss raus.** Das Kochbuch von sglang-omni warnt
ausdrücklich: *"any leftover cubin wheel fails MiniMax DIT import"*. Das
Basisimage bringt genau so ein Rest-Wheel mit.

**Der Modellspeicher bleibt read-only.** sglang-omni normalisiert beim Start
`qwen_7B/qwen_7B/config.json` (`model_type` von `mixtral` auf `qwen3`) und
scheitert daran an der schreibgeschützten Einbindung. Statt den Speicher zu
öffnen, blendet `run_music.sh` eine bereits normalisierte Kopie über diese eine
Datei — die Funktion kehrt dann sofort zurück, ohne zu schreiben.

**flash-attn muss nicht gebaut werden.** Das Basisimage bringt `flash-attn-4`
mit, und der Server wählt ohnehin `torch_sdpa`. Ein Source-Build hätte laut
southbyte-image über 100 Minuten gedauert.

## Nutzung

```bash
# Modell starten (Port 8011)
cd serving && ./run_music.sh

# Bereitschaft prüfen
curl http://127.0.0.1:8011/v1/models

# Ein Stück erzeugen
curl http://127.0.0.1:8011/v1/audio/speech \
  -H 'Content-Type: application/json' \
  -d '{"model":"MiniMaxAI--MiniMax-Music3",
       "input":"[Verse]\nDer Nebel liegt noch auf dem Fluss\n[Chorus]\nUnd alles was bleibt ist ein Klang",
       "instructions":"Ruhiger deutscher Akustik-Pop, 90 BPM, A-Moll, warme Gitarren",
       "response_format":"wav","seed":7,"max_new_tokens":750}' \
  -o lied.wav

# Weboberfläche (rein statisch, spricht direkt den Endpoint an)
python3 -m http.server 8080 --directory webui
```

Die Oberfläche unter `webui/index.html` bietet Lyrics mit Abschnitts-Tags,
Caption, Länge, Seed und Format; sie spielt das Ergebnis ab und bietet es zum
Herunterladen an.

**Der Endpunkt ist Betriebssache, nicht Anwendersache.** In der Oberfläche gibt
es dafür kein Eingabefeld — gesetzt wird er ausschließlich in
`webui/config.js`:

```js
window.SOUTHBYTE_MUSIC = { endpunkt: "" };   // leer = aus der Seitenadresse ableiten
```

Bleibt der Wert leer, nimmt die Seite denselben Host, von dem sie geladen wurde,
mit Port 8011. Das ist der Normalfall. Steht der Musik-Server woanders, trägt der
Betreiber ihn dort ein. Der aufgelöste Endpunkt steht im Fuß der Seite, damit
eine Fehlkonfiguration erkennbar bleibt.

## Port

| Port | Dienst |
|---|---|
| 8011 | `serving/run_music.sh` (MiniMax-Music3 über SGLang-Omni) |

8000–8010 sind in der Familie belegt (vLLM, TTS-Adapter, STT-Judges, Bild).

## Lizenz des Modells

MiniMax-Music3 steht unter der **MiniMax-Music3 Community License**. Kommerzielle
Nutzung ist erlaubt, mit zwei Auflagen:

1. Der Name **„MiniMax-Music3"** muss in der Oberfläche eines kommerziellen
   Produkts deutlich sichtbar sein — deshalb steht er in `webui/index.html`
   sowohl im Kopf als auch im Fuß und nicht bloß in einer Fußnote.
2. Ab 20 Mio. USD Jahresumsatz ist eine schriftliche Genehmigung von MiniMax
   erforderlich (`api@minimax.io`).

Erzeugte Audiodateien und `results/` sind per `.gitignore` ausgeschlossen und
bleiben lokal.

**Zur Einordnung:** Die Auflagen unter Abschnitt 3 der Lizenz gelten für
kommerzielle Produkte. Dieses Repo ist ein Proof of Concept und keines. Die
Nennung des Modellnamens steht trotzdem in der Oberfläche — wer den Code als
Grundlage für etwas Kommerzielles nimmt, hat sie damit schon an der richtigen
Stelle und stolpert nicht nachträglich darüber.

## Was hier bewusst fehlt

Kein Nutzerkonto, keine Warteschlange, keine Ratenbegrenzung, keine
Persistenz. Die Oberfläche spricht den Endpunkt direkt an und hält nichts
fest. Wer das ins Netz stellt, stellt einen offenen Generator ins Netz —
für einen Proof of Concept im eigenen Netz genügt das, für alles andere nicht.

Ebenfalls nicht enthalten: eine Evaluation. Die anderen Stacks dieser Familie
messen ihre Modelle (WER für TTS, Prompt-Treue für Bild); für Musik gibt es
hier bisher kein Maß. Was gut klingt, entscheidet vorerst das Ohr.

## Teil der southbyte-Familie

- [southbyte-core](https://github.com/MvdB/southbyte-core) — gemeinsamer Index
- [southbyte-sync](https://github.com/MvdB/southbyte-sync) — HuggingFace-Spiegel → lokaler Modellspeicher
- [southbyte-vllm](https://github.com/MvdB/southbyte-vllm) — vLLM-Runner + LLM-Testplan
- [southbyte-tts](https://github.com/MvdB/southbyte-tts) — TTS/STT-Serving + deutsche Evaluation
- [southbyte-image](https://github.com/MvdB/southbyte-image) — Text-zu-Bild-Serving + Evaluation
- [southbyte-spark-profiles](https://github.com/MvdB/southbyte-spark-profiles) — GB10-Profile, Kernel, Benchmarks
- **southbyte-music** — Text-zu-Musik *(dieses Repo)*

---

Built by [southbyte](https://southbyte.de).

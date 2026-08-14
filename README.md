# southbyte-music

Text-zu-Musik auf dem **NVIDIA DGX Spark** (GB10 SoC, sm_120, 128 GB Unified
Memory, aarch64) — Serving-Adapter plus schlanke Weboberfläche zum Erzeugen
ganzer Stücke aus Text und Beschreibung.

> **Status 2026-08-14: Gerüst, noch nicht auf Hardware verifiziert.**
> Weder der SGLang-Omni-Start auf sm_120 noch die arm64-Tauglichkeit des Images
> sind bisher geprüft. Die Werte in `serving/run_music.sh` sind Ausgangspunkte,
> keine Messwerte.

## Modell

[MiniMaxAI/MiniMax-Music3](https://huggingface.co/MiniMaxAI/MiniMax-Music3) —
hybrides System aus einem globalen 8B-LLM (Qwen3-8B-Basis) für die Struktur,
einem lokalen 0,6B-LLM für akustische Details, 2,4B Flow-Matching und einem
123M Flow-VAE-Decoder. Rund 47 GB Gewichte.

| Eigenschaft | Wert |
|---|---|
| Eingabe | Lyrics mit Abschnitts-Tags + Beschreibung (Genre, BPM, Tonart, Stimmung) |
| Ausgabe | 32 kHz, 16 bit, Stereo-WAV |
| Maximale Länge | 5 Minuten (9000 akustische Frames bei 25 fps) |
| Kontext | 5000 Tokens Prompt |
| Streaming | nicht unterstützt |

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

Die Oberfläche unter `webui/index.html` bietet Textfeld mit Abschnitts-Tags,
Beschreibung, Länge, Seed und Endpunkt; sie spielt das Ergebnis ab und bietet es
zum Herunterladen an.

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

# southbyte-music

Text-to-music on an **NVIDIA DGX Spark**: lyrics and a style description go in, a
finished song comes out — locally, on one machine. A serving adapter for
[MiniMaxAI/MiniMax-Music3](https://huggingface.co/MiniMaxAI/MiniMax-Music3) plus a
small web interface.

> **Proof of concept, not a product.** This repository shows *that*
> MiniMax-Music3 runs on a DGX Spark and *how*. No guaranteed availability,
> fitness or output quality, no support, no roadmap.

## What it does

- **In:** lyrics with section tags (`[Intro]`, `[Verse]`, `[Chorus]`, …) and a
  caption describing genre, mood and instrumentation.
- **Out:** a complete song with vocals — arrangement, singing and mix in one pass.
- A web interface with a worked example built in, and an OpenAI-compatible API
  (`/v1/audio/speech`) if you would rather script it.
- Nothing leaves the machine.

It does **not** take audio as input, separate stems, clone voices or continue an
existing track.

Measured on a DGX Spark (GB10), not estimated:

| | |
|---|---|
| Length | up to **5:00** per piece — 7500 frames at 25 fps, the range the model was trained for |
| Generation time | **5–6× the playing time**; a three-minute song is about a quarter of an hour |
| Server start | **160 s** until it answers |
| Length from lyrics | about **1.62 sung syllables per second** — that is how the interface turns a lyric sheet into a frame count |
| Output | 32 kHz stereo, 16 bit WAV |

How each number was arrived at, including the one that was wrong the first time:
[`docs/modell.md`](docs/modell.md).

## Getting it running

```bash
# 1. Fetch the model (~54 GB on disk). It is deliberately not in the image.
hf download MiniMaxAI/MiniMax-Music3 --local-dir ~/hf_models/MiniMaxAI--MiniMax-Music3

# 2. Start the model server and the web interface
docker compose up -d

# 3. Ready after about 160 s
docker compose logs -f
```

Then open <http://127.0.0.1:8080> and press **Musik erzeugen** — the interface
ships with a complete example, so the first run needs no input. `docker compose
down` stops both again.

You need **Docker with GPU access** and a CUDA device with ≥ 60 GB. Developed on
a DGX Spark (GB10, sm_120, 128 GB unified memory, aarch64); anything else should
work but is untested. The images are public — no login, no token. Or drive the
OpenAI-compatible API directly:

```bash
curl http://127.0.0.1:8011/v1/audio/speech \
  -H 'Content-Type: application/json' \
  -d '{"model":"MiniMaxAI--MiniMax-Music3",
       "input":"[Verse]\nGreen light rising in the engine room\n[Chorus]\nSouth Byte - a heartbeat in the wire",
       "instructions":"Basic Attributes: key is E minor, Melodic Heavy Metal.\nVocals: clean powerful female lead.",
       "response_format":"wav","seed":7,"max_new_tokens":750}' \
  -o song.wav
```

Ports, image tags, plain `docker run` and building it yourself:
[`docs/docker.md`](docs/docker.md). On a cluster:
[`docs/kubernetes.md`](docs/kubernetes.md).

## What to watch out for

**Describe the arrangement, not just the genre.** Same lyrics, same frames, two
seeds, only the caption form differs: describing the sections pulled the spread
between seeds from **0.325 down to 0.055** and widened the stereo image from
**0.46 to 0.54**. The seed still picks melody and timbre — but no longer the
shape of the piece. Numbers and recipe:
[`eval/caption-ab/`](eval/caption-ab/ERGEBNIS.md).

**It is slow, and predictably so.** A three-minute song is about a quarter of an
hour. The interface estimates it up front rather than leaving you guessing.

**Choose the format you need.** SGLang-Omni v0.1.3 preserves the model's stereo
signal in non-streaming MP3, FLAC, Opus and AAC responses. Streaming audio remains
mono by design. Background: [`docs/upstream-issue-mono.md`](docs/upstream-issue-mono.md).

**Write the caption in English.** A German one pulls the result audibly towards
German-language pop — *"Melodischer Metal, 150 BPM"* landed closer to 1980s Neue
Deutsche Welle than to metal. Lyrics may be any language; with German,
transliterate the umlauts ([`docs/modell.md`](docs/modell.md)).

**BPM is a wish, not a setting.** Four runs demanding 150 BPM explicitly hit it
in none. Write the number down anyway — it costs nothing and reads as a style
signal — but do not build on it. Measured:
[`eval/caption-ab/`](eval/caption-ab/ERGEBNIS.md).

**There is no authentication, no queue, no rate limiting and no persistence.**
Putting this on a public network means putting an open generator on a public
network — anyone who can reach it can spend your GPU. Fine on a private network
for a proof of concept, not fine for anything else.

## Licence

Code in this repository is **MIT**. The model, its weights and its output are
covered by the **MiniMax-Music3 Community License** — that licence travels with
the model, not with this repository. Two obligations come with it if you build
something commercial on it:

1. The name **"MiniMax-Music3"** must be clearly visible in the interface. It is
   already in `webui/index.html`, header and footer, and CI fails if it
   disappears — a legal obligation, not decoration.
2. Above 20 M USD annual revenue, written permission from MiniMax is required
   (`api@minimax.io`).

**One exception, and it is signposted.** The 1019 reference captions under
`.claude/skills/musik-caption/` come unchanged from MiniMax-AI under the same
licence, with its `LICENSE` alongside them — terms and the exact split between
their text and ours: [`HERKUNFT.md`](.claude/skills/musik-caption/HERKUNFT.md).

Generated audio and `results/` are gitignored and stay local.

## Where this is going

Nowhere in particular, and that is deliberate. The question it set out to answer
— *does MiniMax-Music3 run on a DGX Spark, and what does it cost?* — is answered
above, with numbers. What is missing is named rather than planned:

- **No evaluation of the model.** The other stacks in this family measure theirs
  (WER for TTS, prompt fidelity for image). For music there is no comparable
  metric here; what sounds good is decided by ear. The one narrow exception
  compares caption *forms*, not model quality:
  [`eval/caption-ab/`](eval/caption-ab/ERGEBNIS.md).
- **The v0.1.3 image has not been run on the GB10 yet.** Upstream's deterministic
  CPU tests cover stereo encoding, and `serving/pruefe_image.sh` now asks the
  server for an MP3 and fails if it comes back mono — so the check exists. What is
  missing is the run itself, on the hardware.

Issues and pull requests are welcome; nobody is on call for them.

## Going deeper

| | |
|---|---|
| [`docs/docker.md`](docs/docker.md) | Images and tags, compose options, running without compose, building it yourself, ports, how CI builds both architectures |
| [`docs/kubernetes.md`](docs/kubernetes.md) | The Helm chart, why the model lives in a PersistentVolume, the settings that will bite you if you change them, security posture |
| [`docs/modell.md`](docs/modell.md) | What the model is, and everything measured on the GB10: startup, generation time, frames from syllables, early stop, caption findings |
| [`docs/oberflaeche.md`](docs/oberflaeche.md) | The web interface and the one setting that matters, the endpoint |
| [`docs/entscheidungen.md`](docs/entscheidungen.md) | Why SGLang-Omni and not a custom adapter, why not ComfyUI |
| [`docs/sglang-omni-notizen.md`](docs/sglang-omni-notizen.md) | Rebuilding the serving image: version coupling, the read-only model store, and four other things that are not in anyone's documentation |
| [`docs/upstream-issue-mono.md`](docs/upstream-issue-mono.md) | The resolved mono-output bug and its scope |

Writing captions is its own craft. The `musik-caption` skill under
`.claude/skills/` carries the full schema, the syllable arithmetic and 1000
reference captions across 18 style families — it loads by itself when Claude Code
works in this repository.

## Part of the southbyte family

- [southbyte-core](https://github.com/MvdB/southbyte-core) — shared index
- [southbyte-sync](https://github.com/MvdB/southbyte-sync) — HuggingFace mirror → local model store
- [southbyte-vllm](https://github.com/MvdB/southbyte-vllm) — vLLM runner + LLM testplan
- [southbyte-tts](https://github.com/MvdB/southbyte-tts) — TTS/STT serving + German evaluation
- [southbyte-image](https://github.com/MvdB/southbyte-image) — text-to-image serving + evaluation
- [southbyte-results](https://github.com/MvdB/southbyte-results) — cross-modality results site
- [southbyte-spark-profiles](https://github.com/MvdB/southbyte-spark-profiles) — GB10 profiles, kernels, benchmarks
- **southbyte-music** — text-to-music *(this repository)*

---

Built by [southbyte](https://southbyte.de).

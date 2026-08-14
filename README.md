# southbyte-music

Text-to-music on an **NVIDIA DGX Spark** — a serving adapter for
[MiniMaxAI/MiniMax-Music3](https://huggingface.co/MiniMaxAI/MiniMax-Music3) plus
a small web interface that turns lyrics and a style description into a complete
song, locally, on one machine.

> **Proof of concept, not a product.** This repository shows *that*
> MiniMax-Music3 runs on a DGX Spark and *how*. There is no guaranteed
> availability, fitness or output quality, no support and no roadmap. Expect to
> get your hands dirty if you rebuild it.

Everything below was measured on the machine, not estimated or copied from a
model card. Where a number turned out to be wrong the first time, that is said
so explicitly — the wrong assumptions are usually the useful part.

## Quick start

```bash
# 1. Fetch the model (~54 GB on disk)
hf download MiniMaxAI/MiniMax-Music3 --local-dir ~/hf_models/MiniMaxAI--MiniMax-Music3

# 2. Build the serving image (~2 min; the base image brings the stack)
docker build -t spark-sglang-omni:v1 -f serving/Dockerfile.music serving/

# 3. Start the server on port 8011 (ready after ~160 s)
cd serving && ./run_music.sh
curl http://127.0.0.1:8011/v1/models

# 4. Serve the web interface
python3 -m http.server 8080 --directory webui
```

Then open <http://127.0.0.1:8080> and press **Musik erzeugen**. The interface
ships with a complete example — lyrics, caption, length — so the first run needs
no input at all.

Or drive the API directly; it is OpenAI-compatible:

```bash
curl http://127.0.0.1:8011/v1/audio/speech \
  -H 'Content-Type: application/json' \
  -d '{"model":"MiniMaxAI--MiniMax-Music3",
       "input":"[Verse]\nGreen light rising in the engine room\n[Chorus]\nSouth Byte - a heartbeat in the wire",
       "instructions":"Basic Attributes: bpm is 150, key is E minor, Melodic Heavy Metal.\nVocals: clean powerful female lead.",
       "response_format":"wav","seed":7,"max_new_tokens":750}' \
  -o song.wav
```

## Requirements

| | |
|---|---|
| Hardware | NVIDIA DGX Spark (GB10 SoC, sm_120, 128 GB unified memory, aarch64). Any other CUDA device with ≥ 60 GB should work, but is untested |
| Model | [MiniMaxAI/MiniMax-Music3](https://huggingface.co/MiniMaxAI/MiniMax-Music3), ~54 GB on disk |
| Runtime | Docker with GPU access |
| Model store | `~/hf_models/<owner>--<model>`, overridable via `HF_MODELS_DIR` |

The model directory is mounted **read-only** — this repository never writes into
the model store.

## The model

[MiniMaxAI/MiniMax-Music3](https://huggingface.co/MiniMaxAI/MiniMax-Music3) is a
hybrid system: a global 8B LLM (Qwen3-8B based) for song structure, a local 0.6B
LLM for acoustic detail, 2.4B of flow matching, and a 123M Flow-VAE decoder.
Roughly 47 GB of weights.

| Property | Value |
|---|---|
| Input | Lyrics with section tags + a caption (genre, BPM, key, mood) |
| Output | 32 kHz, 16 bit, stereo WAV |
| Maximum length | **5 minutes** = 7500 frames at 25 fps — that is what the model is built and trained for. The hard limit under *Limitations* is higher (9000 frames = 6:00), but past five minutes you leave the trained range |
| Context | 5000 prompt tokens |
| Streaming | not supported |

## Measured on the DGX Spark (GB10)

| | |
|---|---|
| Server start | 160 s |
| Generation time | roughly **5–6× the playing time**; four data points: 250/750/1500/3839 frames → 85/157/356/831 s |
| Frames from text | about **1.62 sung syllables per second** — the built-in example (22 lines, 234 syllables) lands at 4350 frames ≈ 2:54 with 20 % headroom |
| Early stop | verified: asking for 4000 frames, the server reported `AR done frames=3839 finish_reason=stop` — rounding up generously is free |
| Attention backend | `torch_sdpa` — flash-attn is never used |
| WAV output | 32 kHz, **stereo**, 16 bit |
| MP3 output | 32 kHz, **mono**, 40 kbit/s (see below) |

The interface estimates **22 s of fixed cost plus 0.211 s per frame** and labels
the result as an estimate. A first version was fitted to the two short runs only
(250 and 750 frames) and came out a quarter too low at 1500 frames — short runs
do not extrapolate to long ones. The fourth data point at 3839 frames is what
straightened the line.

Length is capped at **7500 frames**. The `max` attribute only stops the arrow
keys, so the interface caps again before sending. If the text needs more than
5:00, it says so and asks you to cut, rather than truncating silently.

### MP3 is mono — a limitation of sglang-omni, not of the model

In `sglang_omni/client/audio.py`, every compressed format is pinned to
`stream.layout = "mono"`, and multi-channel input is averaged before it gets
there. The comment in the code names the reason — *"Streaming chunks are mono"* —
and it is a fair one: that path was written for speech streaming, where mono is
the norm. `encode_wav` in the same file handles two channels correctly.

For a model whose output is 32 kHz **stereo** by design, the most convenient
output format therefore discards half the signal, silently. The interface
defaults to **WAV** for that reason; MP3 stays available with the caveat next to
it.

For a stereo MP3, re-encode the WAV afterwards. The ffmpeg for it is already in
the serving image, so nothing needs installing on the host:

```bash
serving/wav_zu_mp3.sh song.wav              # -> song.mp3, 192 kbit/s, stereo
serving/wav_zu_mp3.sh song.wav final.mp3 320
```

The script checks its own output and aborts if it came out single-channel after
all. A draft bug report for the upstream project is in
[`docs/upstream-issue-mono.md`](docs/upstream-issue-mono.md).

### Write the caption in English

Every example from the vendor is in English, and it matters more than it looks.
A German style description pulled the result audibly towards German-language pop
— *"Melodischer Metal, 150 BPM, verzerrte Gitarrenwand"* produced something
closer to 1980s Neue Deutsche Welle than to metal. The same lyrics with an
English caption in the documented format hit the genre far better.

Lyrics in other languages are fine; only the caption needs to be English. Two
things to expect with German lyrics, both observed: the model sings *BYTE* as
though it were German, and umlauts have to be transliterated or they get
swallowed — which then looks odd in the text box.

The documented caption format, and the more specific the better:

```
Basic Attributes: bpm is 150, key is E minor, Melodic Heavy Metal.
Emotional Progression: driving and defiant from the first bar, building into a
soaring anthemic chorus.
Sonics: heavily distorted rhythm guitars, double kick drums, orchestral string
pad under the chorus, loud and tightly compressed.
Vocals: clean powerful female lead, layered harmonies in the chorus.
```

## The web interface

`webui/` is static — no build step, no dependencies. It offers lyrics with
section tags, the caption, length, seed and output format, then plays the result
and offers it for download. The length field can be derived from the lyrics.

**The endpoint is an operator's concern, not the user's.** There is deliberately
no input field for it. It is set in `webui/config.js` and nowhere else:

```js
window.SOUTHBYTE_MUSIC = { endpunkt: "" };   // empty = derive from the page address
```

Left empty, the page uses the host it was served from with port 8011 — the
normal case. If the music server lives elsewhere, the operator puts it there.
The resolved endpoint is shown in the page footer, so a misconfiguration stays
visible without being editable.

The interface is in German; the code and configuration are documented in German
too, which is the house style across this family of repositories.

## Design decisions

**Why SGLang-Omni instead of a custom adapter.** The vendor serves
MiniMax-Music3 through SGLang-Omni, which exposes `/v1/audio/speech` **natively**
— the same OpenAI-compatible interface the TTS adapters in this family already
speak. A later evaluation harness only needs a different URL, and no adapter has
to be written that already exists. Same shape as Voxtral-TTS in
[southbyte-tts](https://github.com/MvdB/southbyte-tts), where vLLM-Omni provides
the endpoint natively.

**Why not ComfyUI**, despite an official workflow template existing: ComfyUI
wants its own repacked weight files (`minimax_music3_dit_fp16.safetensors`,
`…_text_encoder_pruned_int8_convrot…`, `…_dav.safetensors`) spread across
`models/diffusion_models/`, `models/text_encoders/` and `models/vae/`. That is
the same model a second time on disk, in a different format, outside the model
store — and ComfyUI loads it itself, which collides with the serving path.
Headless/API operation is undocumented. As a node editor for trying out
parameters it stays useful; as the foundation for a music interface it does not.

## Notes for anyone rebuilding this

These cost time and are not obvious from the documentation.

**`sgl-omni` is not in the standard image.** The `lmsysorg/sglang` images contain
only `sglang`, `sglang-kernel` and `sglang-router`; there is no `sgl-omni` binary
and no `sglang_omni` module. SGLang-Omni is a separate project, the way vllm-omni
sits next to vllm — hence the extra install step in `serving/Dockerfile.music`.

**The PyPI release does not know MiniMax-Music3.** Version 0.1.1 aborts at
startup with `Config for MiniMaxMusic3ForConditionalGeneration not found in the
pipeline config registry`. Support landed in commit `05e268a4` (2026-08-13),
hence the install from `git main`.

**`flashinfer-cubin` has to go.** The sglang-omni cookbook warns explicitly that
*"any leftover cubin wheel fails MiniMax DIT import"*, and the base image ships
exactly such a leftover wheel.

**The model store stays read-only.** At startup, sglang-omni normalises
`qwen_7B/qwen_7B/config.json` (`model_type` from `mixtral` to `qwen3`) and fails
against a read-only mount. Rather than opening up the store, `run_music.sh`
overlays a single pre-normalised copy of that one file — the function then
returns immediately without writing.

**flash-attn does not need building.** The base image ships `flash-attn-4`, and
the server picks `torch_sdpa` anyway. A source build would have taken over 100
minutes on this hardware.

## Model licence — obligations you inherit

MiniMax-Music3 is covered by the **MiniMax-Music3 Community License**. Commercial
use is permitted, with two conditions:

1. The name **"MiniMax-Music3"** must be clearly visible in the interface of a
   commercial product. It appears in `webui/index.html` in both the header and
   the footer, and CI fails if it disappears — that is a legal obligation, not
   decoration.
2. Above 20 M USD annual revenue, written permission from MiniMax is required
   (`api@minimax.io`).

This repository is a proof of concept and not a commercial product, so the
section 3 obligations do not bite here. The attribution is in the interface
anyway: anyone taking this as a starting point for something commercial already
has it in the right place instead of tripping over it later.

Generated audio and `results/` are gitignored and stay local.

## What is deliberately missing

**There is no authentication, no queue, no rate limiting and no persistence.**
The interface talks to the endpoint directly and stores nothing. Putting this on
a public network means putting an open generator on a public network — anyone
who can reach it can spend your GPU. Fine on a private network for a proof of
concept, not fine for anything else.

Also missing: an evaluation. The other stacks in this family measure their models
(WER for TTS, prompt fidelity for image); for music there is no metric here yet.
What sounds good is decided by ear for now.

## Ports

| Port | Service |
|---|---|
| 8011 | `serving/run_music.sh` (MiniMax-Music3 via SGLang-Omni) |

8000–8010 are taken by the other stacks in this family (vLLM, TTS adapters, STT
judges, image).

## Part of the southbyte family

- [southbyte-core](https://github.com/MvdB/southbyte-core) — shared index
- [southbyte-sync](https://github.com/MvdB/southbyte-sync) — HuggingFace mirror → local model store
- [southbyte-vllm](https://github.com/MvdB/southbyte-vllm) — vLLM runner + LLM testplan
- [southbyte-tts](https://github.com/MvdB/southbyte-tts) — TTS/STT serving + German evaluation
- [southbyte-image](https://github.com/MvdB/southbyte-image) — text-to-image serving + evaluation
- [southbyte-results](https://github.com/MvdB/southbyte-results) — cross-modality results site
- [southbyte-spark-profiles](https://github.com/MvdB/southbyte-spark-profiles) — GB10 profiles, kernels, benchmarks
- **southbyte-music** — text-to-music *(this repository)*

## Licence

Code in this repository is MIT. The model, its weights and its output are covered
by the MiniMax-Music3 Community License linked above — that licence travels with
the model, not with this repository.

---

Built by [southbyte](https://southbyte.de).

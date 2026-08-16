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

Two published images, nothing to build:

```bash
# 1. Fetch the model (~54 GB on disk). It is not in the image — see below.
hf download MiniMaxAI/MiniMax-Music3 --local-dir ~/hf_models/MiniMaxAI--MiniMax-Music3

# 2. Start the model server and the web interface
docker compose up -d

# 3. Watch it come up — ready after about 160 s
docker compose logs -f
```

Then open <http://127.0.0.1:8080> and press **Musik erzeugen**. The interface
ships with a complete example — lyrics, caption, length — so the first run needs
no input at all.

The images are public: no login, no token. `docker compose down` stops both
again. More knobs, and how to build it yourself instead, under
[*Running it with Docker*](#running-it-with-docker).

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

### Ask for WAV, not MP3

The model produces 32 kHz **stereo**. Every compressed format the server offers
comes back **mono** — half the signal, discarded silently. That is a limitation
of the serving stack, not of the model, and the interface defaults to WAV
because of it.

For a stereo MP3, re-encode afterwards. The ffmpeg for it is already in the
serving image, so nothing needs installing on the host:

```bash
serving/wav_zu_mp3.sh song.wav              # -> song.mp3, 192 kbit/s, stereo
serving/wav_zu_mp3.sh song.wav final.mp3 320
```

The script checks its own output and aborts if it came out single-channel after
all. Where exactly this happens in the code, and why, is in
[`docs/upstream-issue-mono.md`](docs/upstream-issue-mono.md); reported upstream
as [sgl-project/sglang-omni#1549](https://github.com/sgl-project/sglang-omni/issues/1549),
still open.

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

### BPM is a wish, not a setting

The example above asks for 150 BPM and does not get it. Four generations that
demanded 150 explicitly — twice as `Basic Attributes: bpm is 150`, twice in the
long caption form — produced no meaningful pulse at 150 in any of them. The
autocorrelation of the onset envelope sits at 0.017–0.081 there, against
0.115–0.210 at whatever tempo each track actually settled on. That method cannot
resolve an octave, so 87 against 174 stays open; 150 does not.

Write the number down anyway — it costs nothing and reads as a style signal. Just
do not build on it, and if the tempo really matters, measure the result instead of
trusting the caption.

One genre, one set of lyrics, four runs. Numbers, method and the two captions:
[`eval/caption-ab/`](eval/caption-ab/ERGEBNIS.md) (in German).

### The long form is worth it when the arrangement matters

The four-line form above is the quick one. The vendor's reference captions use a
longer schema — three headings with named fields, the arrangement described
section by section. In the same A/B run, the long form came out ahead in two
places and behind in none:

- **The structure becomes reproducible.** Energy curves across two seeds were
  nearly identical for the long form and ran against each other for the short one
  (mean deviation 0.055 against 0.325). Describe the arrangement and the seed
  still picks melody and timbre — but no longer the shape of the piece.
- **The mix follows the instruction.** Hard panning and strings placed behind the
  guitars showed up as measurably wider stereo (0.54 against 0.46), with no
  overlap between the variants.
- Loudness and dynamics did not differ, and the tempo missed either way.

The full schema, the syllable arithmetic and the pitfalls are in the
`musik-caption` skill under `.claude/skills/` — it loads by itself when Claude
Code works in this repository.

## The web interface

`webui/` is static — no build step, no dependencies. It offers lyrics with
section tags, the caption, length, seed and output format, then plays the result
and offers it for download. The length field can be derived from the lyrics.

**The endpoint is an operator's concern, not the user's.** There is deliberately
no input field for it. It is set in `webui/config.js` and nowhere else:

```js
window.SOUTHBYTE_MUSIC = { endpunkt: "" };   // empty = derive from the page address
```

Three cases:

| Value | Meaning |
|---|---|
| `""` | derive from the page address: same host, port 8011. For serving `webui/` straight off the disk, without a proxy |
| `"/"` | same origin as the page, so through a reverse proxy. This is what compose and the Kubernetes chart both use |
| a URL | wherever the music server actually is |

In the container the file is written at startup from `SOUTHBYTE_ENDPUNKT`, which
defaults to `/`. That default arrived after `v0.1.0`, so image tag `0.1.0` still
ignores the variable — one more reason the pinned tag in `compose.yaml` is
`0.1.1`.

The resolved endpoint is shown in the page footer, so a misconfiguration stays
visible without being editable.

The interface is in German; the code and configuration are documented in German
too, which is the house style across this family of repositories.

## Running it with Docker

This is the common case on a single machine, and the one `compose.yaml` is for.
Two images, built natively for `linux/amd64` and `linux/arm64` and published to
GHCR:

| Image | Contents | Size |
|---|---|---|
| `ghcr.io/mvdb/southbyte-music` | the model server | 26.5 GB unpacked |
| `ghcr.io/mvdb/southbyte-music-webui` | nginx with the interface and a reverse proxy | 54 MB |

Both are **public** — `docker pull` needs no login and no token.

Tags: `0.1.1` and `0.1` come from git tags, `main` follows the default branch,
`latest` tracks `main`, and `sha-<short>` pins an exact commit. `compose.yaml`
pins a version tag on purpose; `main` and `latest` move under you by design.

The server image is large because the SGLang base image is 24.6 GB of it. That
is not something this repository can trim: the version is pinned to
`sglang==0.5.16`, which is what `sglang-omni` requires.

### What compose sets up

`southbyte-music` gets the GPU, mounts the model store **read-only** and
publishes the API on 8011. `webui` is nginx: it serves the page and proxies
`/v1/` through to the server, so the browser only ever talks to one address —
no CORS, no second port to expose. Knobs, all optional:

| Variable | Default | |
|---|---|---|
| `SOUTHBYTE_MUSIC_VERSION` | `0.1.1` | tag for both images |
| `HF_MODELS_DIR` | `$HOME/hf_models` | where the model lives |
| `MODEL_DIR` | `MiniMaxAI--MiniMax-Music3` | the directory inside it |
| `MUSIK_PORT` / `WEBUI_PORT` | `8011` / `8080` | host ports |

The model is deliberately **not** in the image. It is 54 GB — that would have to
move on every rebuild and every pull, and in Kubernetes it is data rather than
code anyway.

Measured on the DGX Spark with `compose.yaml` as it stands: server ready after
160 s, a 10 s piece generated through the nginx proxy in 49 s, output 32 kHz
stereo 16 bit.

### Without compose

`serving/run_music.sh` starts the server alone. It does what compose does, plus
one thing compose deliberately does not: it can load a machine profile from
[southbyte-spark-profiles](https://github.com/MvdB/southbyte-spark-profiles).

```bash
cd serving && ./run_music.sh                                   # locally built image
IMAGE=ghcr.io/mvdb/southbyte-music:0.1.1 ./run_music.sh        # the published one
```

### Building it yourself

```bash
docker build -t southbyte-music:lokal -f serving/Dockerfile.music serving/   # ~2 min
```

The base image brings the stack, so this is mostly a `pip install` and a few
files. Getting that Dockerfile to work took several attempts, and the reasons
are not obvious from anyone's documentation — they are collected in
[`docs/sglang-omni-notizen.md`](docs/sglang-omni-notizen.md).

CI builds both architectures but has no GPU, so it can only prove that things
install. Whether the image *runs* is a separate step, on the hardware:

```bash
serving/pruefe_image.sh                                     # locally built image
serving/pruefe_image.sh ghcr.io/mvdb/southbyte-music:0.1.1  # the published one
```

It pulls, starts, waits for readiness, generates a short piece and checks the
WAV header — 32 kHz, stereo, plausible length. A 200 response only proves that
something came back.

## Running it on Kubernetes

There is a Helm chart under `charts/southbyte-music`, using the same two images.

```bash
# From the published chart — resolves to the newest release
helm install musik oci://ghcr.io/mvdb/charts/southbyte-music \
  --namespace musik --create-namespace

# Pin a version
helm install musik oci://ghcr.io/mvdb/charts/southbyte-music --version 0.1.1 \
  --namespace musik --create-namespace

# Or from a checkout
helm install musik charts/southbyte-music \
  --namespace musik --create-namespace
```

Every push to `main` also publishes a SemVer *pre-release* (`0.1.1-main.3`).
Helm ignores those unless you pass `--devel` or name one with `--version`, so
plain `helm install` always lands on a tagged release and never on whatever was
merged last.

A released chart pins its images to that release's version tag, so a given chart
version always deploys exactly those images and cannot drift onto a newer build.
A checkout instead uses whatever `Chart.yaml` says, which on `main` is the moving
`main` tag.

The first start takes a while — the model has to reach the volume first, see
below — and the chart's `NOTES.txt` tells you which log to watch.

### The model is not in the image

It is 54 GB. An image that size is not something a cluster pulls onto a node in
any reasonable time, and every rebuild would carry it again. In Kubernetes the
model is *data*, not code: it lives in a PersistentVolume, and an initContainer
fills it.

That initContainer is idempotent in two stages. If the completion marker is
present, nothing happens at all — no network traffic, and the pod starts in
seconds. That is the normal case for every restart, rescale and node change. If
the marker is missing, `hf download` fetches what is not there; that step is
itself resumable, so an interrupted download continues rather than restarting.

The marker is written last, on purpose. If the download breaks off, it is
absent, and the next start picks up the thread instead of treating half a model
as complete.

The initContainer also normalises the backbone config (`model_type` from
`mixtral` to `qwen3`). SGLang-Omni would otherwise attempt that itself at
startup and fail against a read-only mount. Doing it here means the server can
mount the volume read-only, which it does.

### Things that will bite you if you change them

**`terminationGracePeriodSeconds: 1800`.** Five minutes of music is around 27
minutes of computation. The Kubernetes default of 30 s would cut off every
generation in progress on any rollout, restart or node drain.

**The liveness probe is the most dangerous setting in the chart.** `/health`
does answer while a generation is running — verified; it reports the number of
in-flight requests. If that were not the case, this probe would kill every long
piece it was asked to produce. The thresholds are deliberately generous anyway.

**The startup probe allows 600 s.** The server is ready after about 160 s
measured. Without a startup probe, the liveness probe would have to tolerate
that same delay and could then not detect a genuinely hung process for minutes.

**`strategy: Recreate`, not RollingUpdate.** With `ReadWriteOnce` the model
volume binds to one pod; a second would sit in Pending forever. And even with
`ReadWriteMany`, a second pod means a second GPU.

**The PVC survives `helm uninstall`** (`helm.sh/resource-policy: keep`). Those
54 GB would otherwise have to be fetched again. Delete it by hand if you mean it.

### One origin, not two

nginx proxies `/v1/` through to the model server, so the browser only ever talks
to one address. That is why `webui.endpunkt` defaults to `"/"` — same origin as
the page. No second port to expose, no CORS, one Ingress instead of two.

If you put an Ingress in front of it, raise its timeouts too. The nginx defaults
of 60 s would return a 504 on any longer piece while the server is still happily
working:

```yaml
ingress:
  annotations:
    nginx.ingress.kubernetes.io/proxy-read-timeout: "2400"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "2400"
```

### Building and publishing

CI builds both architectures **natively** — `ubuntu-24.04` for amd64 and
`ubuntu-24.04-arm` for arm64 — and merges the two into one manifest list. No
QEMU, so no hours-long emulated build.

The arm64 runners are free for public repositories, which is what makes this
approach viable here. Emulating arm64 on an amd64 runner would take hours for a
stack this size; a native runner takes about as long as building locally. On a
private repository these runners are billable, and a fork would need either the
budget or a fallback to QEMU.

Two things had to be worked around, and the first attempt died on both:

**The image is 26.5 GB unpacked**, almost all of it the SGLang base. A GitHub
runner has around 14 GB free on `/`, so the job ran out of disk so thoroughly
that the runner could not write its own log. The workflow now clears the
preinstalled toolchains it never touches and moves Docker's data root onto the
runner's large second disk before building.

**GHCR paths must be lowercase.** `github.repository_owner` gives the name as
GitHub spells it — `MvdB` — and `docker push ghcr.io/MvdB/…` fails with
*repository name must be lowercase*. The workflow lowercases it.

There is no Actions cache for these builds. It holds 10 GB per repository, a
26 GB image does not fit, and the only layers that are ours are a `pip install`
and a few files — faster to rebuild than to fetch from a cache that would be
evicted every run anyway.

**The build needs no GPU.** It installs packages and runs an import guard; CUDA
is only touched at runtime. What CI therefore *cannot* tell you is whether the
thing actually runs on a card — that is `serving/pruefe_image.sh`, under
[*Building it yourself*](#building-it-yourself). Last run on the DGX Spark:
ready after 166 s, 250 frames in 50 s, output 32 kHz stereo.

The `linux/amd64` image builds but has never run anywhere — there is no x86 GPU
here.

### Security posture

Non-root (uid 1000), `allowPrivilegeEscalation: false`, all capabilities
dropped, `seccompProfile: RuntimeDefault`, no API token mounted. The web UI runs
with `readOnlyRootFilesystem: true`; the model server does not, and that is an
honest `false` rather than an aspirational `true` — Torch and Triton compile
kernels at runtime and need writable paths. Those caches live in emptyDir
volumes so nothing persists into an image layer.

An optional NetworkPolicy (`networkPolicy.enabled=true`) restricts the model
server to traffic from the web UI. It is off by default because without a CNI
that enforces policies it does nothing but suggest safety that is not there.

None of this adds authentication. See *What is deliberately missing*.

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

Also missing: an evaluation of the model. The other stacks in this family measure
theirs (WER for TTS, prompt fidelity for image); there is no comparable metric for
music here, and what sounds good is still decided by ear.

What does exist is narrower: [`eval/caption-ab/`](eval/caption-ab/ERGEBNIS.md)
compares two caption forms over four generations and measures tempo, stereo width,
crest factor and the energy arc. That says something about how to write a caption.
It says nothing about how good the model is.

## Ports

| Port | Service | Set by |
|---|---|---|
| 8011 | the model server (MiniMax-Music3 via SGLang-Omni) | `MUSIK_PORT`, or `HOST_PORT` for `run_music.sh` |
| 8080 | the web interface | `WEBUI_PORT` |

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

**One exception, and it is signposted.** `.claude/skills/musik-caption/references/`
and `templates/` are 1019 files taken unchanged from
[`music-caption-rewriter`](https://github.com/MiniMax-AI/MiniMax-Music3/tree/main/skills/music-caption-rewriter)
in MiniMax-AI's repository — a genre router, 18 family indexes and 1000 reference
captions. They carry the same MiniMax-Music3 Community License, which permits
redistribution as long as the notice travels along; it does, as `LICENSE` in that
directory. The obligations that come with it, including the commercial ones, are
spelled out in
[`.claude/skills/musik-caption/HERKUNFT.md`](.claude/skills/musik-caption/HERKUNFT.md).
Everything else under that path, `SKILL.md` included, is our own text and MIT like
the rest.

---

Built by [southbyte](https://southbyte.de).

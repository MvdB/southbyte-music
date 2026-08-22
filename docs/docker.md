# Running it with Docker

The quick start in the [README](../README.md) is `docker compose up -d`. This page
is everything behind that: what the images are, what compose sets up, how to run
without it, and how to build your own.

## Requirements

| | |
|---|---|
| Hardware | NVIDIA DGX Spark (GB10 SoC, sm_120, 128 GB unified memory, aarch64). Any other CUDA device with ≥ 60 GB should work, but is untested |
| Model | [MiniMaxAI/MiniMax-Music3](https://huggingface.co/MiniMaxAI/MiniMax-Music3), ~54 GB on disk |
| Runtime | Docker with GPU access |
| Model store | `~/hf_models/<owner>--<model>`, overridable via `HF_MODELS_DIR` |

The model directory is mounted **read-only** — this repository never writes into
the model store.

## The images

Two, built natively for `linux/amd64` and `linux/arm64` and published to GHCR:

| Image | Contents | Size |
|---|---|---|
| `ghcr.io/mvdb/southbyte-music` | the model server | 26.5 GB unpacked |
| `ghcr.io/mvdb/southbyte-music-webui` | nginx with the interface and a reverse proxy | 54 MB |

Both are **public** — `docker pull` needs no login and no token.

Tags: `0.1.3` and `0.1` come from git tags, `main` follows the default branch,
`latest` tracks `main`, and `sha-<short>` pins an exact commit. `compose.yaml`
pins a version tag on purpose; `main` and `latest` move under you by design.

| Tag | Moves when | Use it for |
|---|---|---|
| `0.1.3`, `sha-<short>` | never | a run whose result has to stay attributable |
| `0.1` | a release is tagged | unattended updates that should stay on releases |
| `latest`, `main` | every push to `main` | following the branch head deliberately |

If something updates the images for you — Watchtower, a Kubernetes image
policy, a nightly `docker compose pull` — `0.1` is usually the tag you want:
it needs no maintenance like `latest`, but it does not hand you an untagged
work-in-progress build either. Whichever moving tag you pick, record the
**digest** with the results rather than the tag, because the tag alone no
longer identifies what ran:

```bash
docker inspect --format '{{index .RepoDigests 0}}' southbyte-music
```

That matters more than it sounds: a change of server version demonstrably
changes the output at a fixed seed, while two runs on the same version are
identical to the last digit. See
[`../eval/caption-ab/ERGEBNIS.md`](../eval/caption-ab/ERGEBNIS.md); `lauf.sh`
records the digest of every generation for exactly this reason.

```bash
docker buildx imagetools inspect ghcr.io/mvdb/southbyte-music:0.1.3   # both platforms
```

The server image is large because the SGLang base image is 24.6 GB of it. That is
not something this repository can trim: the version is pinned to `sglang==0.5.16`,
which is what `sglang-omni` requires.

## What compose sets up

`southbyte-music` gets the GPU, mounts the model store read-only and publishes the
API on 8011. `webui` is nginx: it serves the page and proxies `/v1/` through to the
server, so the browser only ever talks to one address — no CORS, no second port to
expose. Knobs, all optional:

| Variable | Default | |
|---|---|---|
| `SOUTHBYTE_MUSIC_VERSION` | `0.1.3` | tag for both images |
| `HF_MODELS_DIR` | `$HOME/hf_models` | where the model lives |
| `MODEL_DIR` | `MiniMaxAI--MiniMax-Music3` | the directory inside it |
| `MUSIK_PORT` / `WEBUI_PORT` | `8011` / `8080` | host ports |

The model is deliberately **not** in the image. It is 54 GB — that would have to
move on every rebuild and every pull, and in Kubernetes it is data rather than code
anyway.

Measured on the DGX Spark with `compose.yaml` as it stands: server ready after
160 s, a 10 s piece generated through the nginx proxy in 49 s, output 32 kHz stereo
16 bit.

Note that image tag `0.1.0` predates runtime endpoint configuration and ignores
`SOUTHBYTE_ENDPUNKT`; the browser then addresses port 8011 directly instead of
going through the proxy. That is why the pinned tag is `0.1.3`. See
[`oberflaeche.md`](oberflaeche.md).

## Without compose

`serving/run_music.sh` starts the server alone. It does what compose does, plus one
thing compose deliberately does not: it can load a machine profile from
[southbyte-spark-profiles](https://github.com/MvdB/southbyte-spark-profiles).

```bash
cd serving && ./run_music.sh                                   # locally built image
IMAGE=ghcr.io/mvdb/southbyte-music:0.1.3 ./run_music.sh        # the published one
```

## Building it yourself

```bash
docker build -t southbyte-music:lokal -f serving/Dockerfile.music serving/   # ~2 min
```

The base image brings the stack, so this is mostly a `pip install` and a few files.
Getting that Dockerfile to work took several attempts, and the reasons are not
obvious from anyone's documentation — they are collected in
[`sglang-omni-notizen.md`](sglang-omni-notizen.md).

CI builds both architectures but has no GPU, so it can only prove that things
install. Whether the image *runs* is a separate step, on the hardware:

```bash
serving/pruefe_image.sh                                     # locally built image
serving/pruefe_image.sh ghcr.io/mvdb/southbyte-music:0.1.3  # the published one
```

It pulls, starts, waits for readiness, generates a short piece and checks the WAV
header — 32 kHz, stereo, plausible length — then asks for a second, much shorter
one as MP3 and fails if the frame header says mono. A 200 response only proves
that something came back.

## How CI builds and publishes

Both architectures are built **natively** — `ubuntu-24.04` for amd64 and
`ubuntu-24.04-arm` for arm64 — and merged into one manifest list. No QEMU, so no
hours-long emulated build.

The arm64 runners are free for public repositories, which is what makes this
approach viable here. Emulating arm64 on an amd64 runner would take hours for a
stack this size; a native runner takes about as long as building locally. On a
private repository these runners are billable, and a fork would need either the
budget or a fallback to QEMU.

Two things had to be worked around, and the first attempt died on both:

**The image is 26.5 GB unpacked**, almost all of it the SGLang base. A GitHub
runner has around 14 GB free on `/`, so the job ran out of disk so thoroughly that
the runner could not write its own log. The workflow now clears the preinstalled
toolchains it never touches and moves Docker's data root onto the runner's large
second disk before building.

**GHCR paths must be lowercase.** `github.repository_owner` gives the name as
GitHub spells it — `MvdB` — and `docker push ghcr.io/MvdB/…` fails with *repository
name must be lowercase*. The workflow lowercases it.

There is no Actions cache for these builds. It holds 10 GB per repository, a 26 GB
image does not fit, and the only layers that are ours are a `pip install` and a few
files — faster to rebuild than to fetch from a cache that would be evicted every
run anyway.

**The build needs no GPU.** It installs packages and runs an import guard; CUDA is
only touched at runtime. Last check on the DGX Spark: ready after 166 s, 250 frames
in 50 s, output 32 kHz stereo. The `linux/amd64` image builds but has never run
anywhere — there is no x86 GPU here.

## Ports

| Port | Service | Set by |
|---|---|---|
| 8011 | the model server (MiniMax-Music3 via SGLang-Omni) | `MUSIK_PORT`, or `HOST_PORT` for `run_music.sh` |
| 8080 | the web interface | `WEBUI_PORT` |

8000–8010 are taken by the other stacks in this family (vLLM, TTS adapters, STT
judges, image).

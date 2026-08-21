# Serving MiniMax-Music3 through SGLang-Omni

Notes for anyone rebuilding `serving/Dockerfile.music`. These cost time and are
not obvious from anyone's documentation — the first attempt died on most of them.

They live on their own page rather than in the README because they are about the
internals of somebody else's server. Useful when you are building the image,
noise when you just want to generate a song.

## `sgl-omni` is not in the standard image

The `lmsysorg/sglang` images contain only `sglang`, `sglang-kernel` and
`sglang-router`; there is no `sgl-omni` binary and no `sglang_omni` module.
Checked on 2026-08-14 in `lmsysorg/sglang:dev`. SGLang-Omni is a separate
project, the way vllm-omni sits next to vllm — hence the extra install step in
the Dockerfile.

## Use v0.1.3, not the old PyPI release

Version 0.1.1 aborts at startup with

```
Config for MiniMaxMusic3ForConditionalGeneration not found in the pipeline config registry
```

Support landed in commit `05e268a4` (2026-08-13). It is included in v0.1.3, so the
image pins that release commit rather than an unversioned `main` state.

## The versions are coupled, and the base image tag matters

`sglang-omni` v0.1.3 pins exactly `sglang==0.5.16` and `torch==2.11.0`. The base
image is therefore `lmsysorg/sglang:v0.5.16` (arm64 available) and **not** `:dev`,
which ships `sglang 0.0.0.dev1`. A `pip install` into `:dev` would downgrade
sglang and break the kernels compiled into the image. Same trap as vllm/vllm-omni
in [southbyte-tts](https://github.com/MvdB/southbyte-tts), where the minor
versions have to line up.

## `flashinfer-cubin` has to go

The sglang-omni cookbook warns explicitly that *"any leftover cubin wheel fails
MiniMax DIT import"*, and the base image ships exactly such a leftover wheel. The
Dockerfile removes it.

## The model store stays read-only

At startup, sglang-omni normalises `qwen_7B/qwen_7B/config.json` — `model_type`
from `mixtral` to `qwen3`, so that HuggingFace resolves a Qwen3 config. It writes
a `.bak` and rewrites the file to do so, which against a read-only mount fails
with `OSError: [Errno 30] Read-only file system`.

The function returns immediately when `model_type` is already `qwen3`. So instead
of opening up the model store, both `run_music.sh` and `compose.yaml` overlay a
single pre-normalised copy over that one file. The store stays untouched and
read-only, which is the convention across this family of repositories — a serving
tool has no business writing into what the sync manages.

In Kubernetes the same problem is solved differently: there the initContainer
normalises the file on the PersistentVolume, which lets the server mount the
volume read-only.

## flash-attn does not need building

The base image ships `flash-attn-4`, and the server picks `torch_sdpa` anyway. A
source build would have taken over 100 minutes on this hardware, for a backend
that never gets used.

## Compressed non-streaming output preserves stereo

SGLang-Omni v0.1.3 includes #1558. MP3, FLAC, Opus and AAC preserve stereo for
non-streaming responses; the raw PCM streaming contract remains mono. The history
and scope are in [`upstream-issue-mono.md`](upstream-issue-mono.md).

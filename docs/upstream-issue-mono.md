# Compressed output formats preserve stereo in SGLang-Omni v0.1.3

A record of the mono-output bug fixed in SGLang-Omni v0.1.3.

**Fixed upstream:** [sgl-project/sglang-omni#1558](https://github.com/sgl-project/sglang-omni/pull/1558)
closed [#1549](https://github.com/sgl-project/sglang-omni/issues/1549) on 2026-08-17.
The release v0.1.3 contains the fix.

## What happened before v0.1.3

MiniMax Music 3 produces 32 kHz **stereo** audio. Requested with
`response_format: "wav"` the response is stereo, as expected. With `"mp3"`,
`"flac"`, `"opus"` or `"aac"` the same request returns **mono** — one channel of
a two-channel signal, silently downmixed.

## Root cause

In `sglang_omni/client/audio.py`, the compressed-format encoder pins the layout:

```python
stream.layout = "mono"
...
audio.reshape(1, -1), format="fltp", layout="mono"
```

and multi-channel input is averaged before it gets there:

```python
# Streaming chunks are mono; downmix multi-channel payloads
channel_axis = 0 if audio.shape[0] < audio.shape[-1] else -1
audio = audio.mean(axis=channel_axis).astype("float32")
```

`encode_wav` in the same file handles two channels correctly
(`num_channels = int(pcm.shape[0])`), so the limitation is specific to the
compressed path.

The comment names the origin, and it is a reasonable one: this path was written
for speech streaming, where mono is the norm. It predates the arrival of a music
model whose output is stereo by design.

## Why it mattered

For TTS and ASR the behaviour is harmless. For MiniMax Music 3 it means the most
convenient output format discards half the signal — and does so without a
warning, so it is easy to ship a pipeline that quietly loses the stereo image.

## Reproduction on the old build

```bash
sgl-omni serve --model-path MiniMaxAI/MiniMax-Music3 --port 8000

for f in wav mp3 flac opus; do
  curl -s http://127.0.0.1:8000/v1/audio/speech \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"MiniMaxAI/MiniMax-Music3\",
         \"input\":\"[Verse]\\nTest\",
         \"instructions\":\"An energetic arena rock anthem at 130 BPM\",
         \"response_format\":\"$f\",\"max_new_tokens\":250}" -o out.$f
  echo -n "$f: "; ffprobe -v error -show_entries stream=channels -of csv=p=0 out.$f
done
```

Observed: `wav: 2`, `mp3: 1`, `flac: 1`, `opus: 1`.

## Workaround for old images

Request WAV and re-encode. `serving/wav_zu_mp3.sh` in this repository does that
with the ffmpeg already present in the serving image, and checks its own output
so a silent fallback to mono cannot slip through.

## Fix in v0.1.3

The merged fix derives the layout from the payload, preserves two channels in
MP3, FLAC, Opus and AAC, and resamples each channel independently. It deliberately
leaves the mono raw-PCM streaming path unchanged. Upstream's CPU regression tests
decode output with distinct 440 Hz and 880 Hz source channels, so they verify audio
content rather than channel metadata alone.

## Environment

- Old build: `sglang-omni` commit `68abc7ee`
- Fixed build: `sglang-omni` v0.1.3, commit `91d4359f`
- `sglang` 0.5.16, torch 2.11.0+cu130
- Base image `lmsysorg/sglang:v0.5.16`, **aarch64**
- NVIDIA GB10 (DGX Spark), sm_120, CUDA 13.0
- Model: `MiniMaxAI/MiniMax-Music3`

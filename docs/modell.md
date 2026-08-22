# The model, and what it actually does on a GB10

Everything on this page was measured on the machine, not estimated or copied
from a model card. Where a number turned out to be wrong the first time, that
is said so — the wrong assumptions are usually the useful part.

## What the model is

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
| MP3 output | 32 kHz, **stereo**, 48 kbit/s — measured on image `0.1.4` (sglang-omni `91d4359f`), non-streaming |

The interface estimates **22 s of fixed cost plus 0.211 s per frame** and labels
the result as an estimate. A first version was fitted to the two short runs only
(250 and 750 frames) and came out a quarter too low at 1500 frames — short runs
do not extrapolate to long ones. The fourth data point at 3839 frames is what
straightened the line.

Length is capped at **7500 frames**. The `max` attribute only stops the arrow
keys, so the interface caps again before sending. If the text needs more than
5:00, it says so and asks you to cut, rather than truncating silently.

## Stereo compressed output

The model produces 32 kHz **stereo**. With SGLang-Omni v0.1.3, non-streaming MP3,
FLAC, Opus and AAC responses preserve both channels. The raw PCM streaming path
remains mono by design.

Verified on the GB10 with `serving/pruefe_image.sh` against image `0.1.4`
(`linux/arm64`, revision `3c78ccd`, sglang-omni `91d4359f`). Same request, both
formats:

```
4/6  WAV  HTTP 200 in 50 s
5/6       32000 Hz, 2 Kanaele, 10.0 s, 1250 KB
6/6  MP3  HTTP 200 in 16 s
          32000 Hz, Stereo, 48 kbit/s, 48 KB
```

The MP3 is a twenty-sixth of the size and keeps both channels, which is what the
whole exercise was about. Note the bitrate: **48 kbit/s**, chosen by the server,
not by the caller — `serving/wav_zu_mp3.sh` is still the way to get a specific
one.

`serving/wav_zu_mp3.sh` remains useful for converting an existing WAV or selecting
a specific MP3 bitrate. The ffmpeg for it is already in the serving image, so
nothing needs installing on the host:

```bash
serving/wav_zu_mp3.sh song.wav              # -> song.mp3, 192 kbit/s, stereo
serving/wav_zu_mp3.sh song.wav final.mp3 320
```

The script checks its own output and aborts if it came out single-channel — the
same check `serving/pruefe_image.sh` runs against the server's own MP3 response,
shared as `serving/pruefe_mp3.py`. The former serving bug is documented in [`upstream-issue-mono.md`](upstream-issue-mono.md):
[sgl-project/sglang-omni#1558](https://github.com/sgl-project/sglang-omni/pull/1558)
closed [#1549](https://github.com/sgl-project/sglang-omni/issues/1549) in v0.1.3.

## Write the caption in English

Every example from the vendor is in English, and it matters more than it looks.
A German style description pulled the result audibly towards German-language pop
— *"Melodischer Metal, 150 BPM, verzerrte Gitarrenwand"* produced something
closer to 1980s Neue Deutsche Welle than to metal. The same lyrics with an
English caption in the documented format hit the genre far better.

Lyrics in other languages are fine; only the caption needs to be English. Two
things to expect with German lyrics, both observed:

- **Transliterate the umlauts.** Otherwise the model swallows them — which then
  looks odd in the text box, but is the lesser evil.
- **English words inside German lines are a mixed bag.** An all-caps brand-style
  word came out pronounced as though it were German. English **proper names**,
  on the other hand, were sung correctly in otherwise German lines in every case
  observed so far — no need to respell them phonetically before trying.

That is a handful of songs, not a study. When a particular word matters, listen
to it once rather than trusting either rule.

The documented caption format, and the more specific the better:

```
Basic Attributes: bpm is 150, key is E minor, Melodic Heavy Metal.
Emotional Progression: driving and defiant from the first bar, building into a
soaring anthemic chorus.
Sonics: heavily distorted rhythm guitars, double kick drums, orchestral string
pad under the chorus, loud and tightly compressed.
Vocals: clean powerful female lead, layered harmonies in the chorus.
```

## BPM is a wish, not a setting

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
[`eval/caption-ab/`](../eval/caption-ab/ERGEBNIS.md) (in German).

## The long form is worth it when the arrangement matters

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

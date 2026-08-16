# Design decisions

Two forks in the road, and why each was taken. Traps encountered while
building the image are in [`sglang-omni-notizen.md`](sglang-omni-notizen.md);
this page is about the choices that came before them.

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

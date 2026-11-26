# Original sound effects

These 15 mono, 24 kHz, 16-bit PCM WAV files are synthesized specifically for
Track Playground by `tools/build_audio.py`, with no third-party recordings or
runtime dependencies. Run `python tools/build_audio.py` to regenerate them.

`diesel`, `electric`, `rolling` and `steam` loop seamlessly. The steam loop
contains four exhaust beats per second at normal pitch; playback scales with
prototype speed and the steam model's driving-wheel circumference. These are
stylized model-railway sounds, not recordings of the named locomotives.

`scripts/audio.gd` reads the generated WAV format directly (44-byte PCM header),
so the portable game also loads new sounds without requiring an editor import.
If replacing these assets, keep that PCM format or update the loader.

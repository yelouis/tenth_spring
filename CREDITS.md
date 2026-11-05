# Credits

## Original Art

The original game sprites in `game/assets/original/` are AI-assisted:
- **Base model:** Qwen-Image-2512 Q8_0 GGUF (unsloth) under Apache-2.0 (`https://huggingface.co/Qwen/Qwen-Image-2512`).
- **LoRA:** Lightning 8-step LoRA V1.0 under Apache-2.0.
- **Code-drawn decals:** The cracks (`decal_cracks`), grass tufts (`decal_tufts`), and creeping vine (`decal_creeper`) were drawn by the project's own code (`tools/art_pipeline/draw_overlays.py`).
- **Human approval:** The human maintainer approved Tier 1 assets on 2026-11-01 (Decision 38) and Tier 2 assets on 2026-11-04 (Decision 49). Complete generation and review metadata for each asset is recorded in `game/assets/original/provenance.json`.

# Credits

## Original Art

The original game sprites in `game/assets/original/` are AI-assisted:
- **Base model:** Qwen-Image-2512 Q8_0 GGUF (unsloth) under Apache-2.0 (`https://huggingface.co/Qwen/Qwen-Image-2512`).
- **LoRA:** Lightning 8-step LoRA V1.0 under Apache-2.0.
- **Code-drawn decals:** The cracks (`decal_cracks`), grass tufts (`decal_tufts`), and creeping vine (`decal_creeper`) were drawn by the project's own code (`tools/art_pipeline/draw_overlays.py`).
- **Human approval:** The human maintainer approved Tier 1 assets on 2026-11-01 (Decision 38) and Tier 2 assets on 2026-11-04 (Decision 49). Complete generation and review metadata for each asset is recorded in `game/assets/original/provenance.json`.

## Terrain Tiles (CC0)

The terrain atlas `game/assets/tiles/original_v1.png` is derived from public-domain pixel art:
- **Source pack:** Kenney (`www.kenney.nl`) — *Roguelike/RPG Pack* (`roguelikeSheet_transparent.png`), released under Creative Commons Zero (`CC0 1.0 Universal`, `http://creativecommons.org/publicdomain/zero/1.0/`).
- **Recolouring:** Recoloured to the Tenth Spring Terrain Palette and composed into 4-bit cardinal mask variants by `tools/art_pipeline/recolour_tiles.py`.

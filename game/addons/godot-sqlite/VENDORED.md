# Vendored godot-sqlite v4.4 GDExtension

- **Source URL**: https://github.com/2shady4u/godot-sqlite/releases/tag/v4.4
- **Release Tag**: `v4.4`
- **Vendored Date**: 2026-10-08
- **Source Archive**: `bin.zip`
- **Archive Size**: 65,986,325 bytes (verified across GitHub release download and direct curl)
- **Archive SHA-256**: `639fd1c20ffaa8545f5341325eedfffa29fa3d8c3861c150aaacbc0478208ae3`
- **Dependencies**: Godot v4.3-stable / SQLite 3.46.1 per the release notes
- **License**: MIT (see `LICENSE.md`)

## Platforms
- **Kept (Desktop)**:
  - macOS (universal debug/release frameworks):
    - `bin/libgdsqlite.macos.template_debug.framework`
    - `bin/libgdsqlite.macos.template_release.framework`
  - Windows (x86_64 debug/release dlls):
    - `bin/libgdsqlite.windows.template_debug.x86_64.dll`
    - `bin/libgdsqlite.windows.template_release.x86_64.dll`
  - Linux (x86_64 debug/release sos):
    - `bin/libgdsqlite.linux.template_debug.x86_64.so`
    - `bin/libgdsqlite.linux.template_release.x86_64.so`
- **Dropped (Mobile & Web)**:
  - Android (arm64, x86_64 debug/release sos)
  - iOS (debug/release xcframeworks + libgodot-cpp xcframeworks)
  - Web (wasm32 debug/release wasm)

## GDExtension Manifest
`gdsqlite.gdextension` is kept unmodified (`compatibility_minimum = "4.3"`, `entry_symbol = "sqlite_library_init"`).

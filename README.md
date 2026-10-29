# OpenScan

Free, open-source LiDAR 3D scanner for iPhone and iPad Pro. No account, no ads, no paywall.

Independent project. It is not affiliated with, derived from, or a copy of any commercial scanning app;
it is written from scratch on Apple's public ARKit scene-reconstruction API.

## Features

- Live LiDAR mesh capture with on-screen mesh overlay
- Wall / floor / ceiling / table / seat / window / door classification
- Library with rename, delete, Quick Look 3D preview
- Export **PLY** (binary, classification colors), **OBJ**, **USDZ**
- Scans are plain files in the Files app (On My iPhone → OpenScan)

## Requirements

iPhone 12 Pro or later, or iPad Pro (2020+), with a LiDAR scanner. iOS 17+. Xcode 26+.

## Build

```sh
brew install xcodegen
xcodegen generate
open OpenScan.xcodeproj
```

Set your own `DEVELOPMENT_TEAM` and bundle id in `project.yml`. Run unit tests with `⌘U` (no LiDAR needed);
live capture only works on a physical LiDAR device — the simulator shows an unsupported state.

## Export notes

- USDZ is written as a single hand-built USDA scene in an uncompressed, 64-byte-aligned archive
  (ModelIO cannot write `.usdz`). Output passes Apple's `usdchecker`.
- Scene units are meters, Y-up (ARKit world frame).

## Roadmap

- Per-vertex color from camera frames (texture capture)
- Binary USDC for smaller files
- Measurement tools

## License

MIT

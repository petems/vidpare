# VidPare

A lightweight native macOS video trimmer built with Swift, SwiftUI, and AVFoundation.

## Motivation

Web-based video trimming tools impose file size limits, require uploads, and rely on slow WASM-based processing. VidPare uses macOS-native AVFoundation for hardware-accelerated video operations, including passthrough remux (near-instant, lossless trimming without re-encoding).

## Features (MVP)

- Open MP4, MOV, M4V files via drag-and-drop or file picker
- Video preview with scrubbing
- Timeline with thumbnail strip and draggable trim handles
- Export formats: MP4 (H.264), MOV (H.264), MP4 (HEVC)
- Quality presets: Passthrough (default, fastest), High, Medium, Low
- Estimated output size in export dialog
- No file size limit

## Requirements

- macOS 14 (Sonoma) or later
- Xcode 15+

## Architecture

```text
SwiftUI Shell (views, timeline, export UI)
    |
VideoEngine (AVAsset, AVMutableComposition, AVAssetExportSession)
    |
AVFoundation (Apple, hardware-accelerated via VideoToolbox)
```

No ffmpeg. No Electron. No WASM.

## Building

Open the project directory in Xcode (`File > Open...` on the repo root) — Xcode natively recognizes the `Package.swift` and provides full IDE support including signing and entitlements. Build with Cmd+B. Alternatively, build from the command line:

```bash
swift build
```

The app targets macOS 14+ with local development signing.

## License

[MIT](LICENSE)

# VidPare

A lightweight native macOS video trimmer built with Swift, SwiftUI, and AVFoundation.

## Motivation

Web-based video trimming tools impose file size limits, require uploads, and rely on slow WASM-based processing. VidPare uses macOS-native AVFoundation for hardware-accelerated video operations, including passthrough remux (near-instant, lossless trimming without re-encoding).

## Features

- Open MP4, MOV, M4V files via drag-and-drop or file picker
- Video preview with scrubbing
- Timeline with thumbnail strip and draggable trim handles
- Export formats: MP4 (H.264), MOV (H.264), MP4 (HEVC)
- Quality presets: Passthrough (default), High, Medium, Low
- Export capability preflight based on current Mac + source media
- Estimated output size in export dialog

## Platform Support

- macOS 14 (Sonoma) or later
- Universal binary releases for both:
  - Apple Silicon (`arm64`)
  - Intel (`x86_64`)

## Codec Notes (Cross-Hardware)

- HEVC export support is capability-driven and can differ by machine.
- Passthrough keeps the source container and source codec.
- If a selected format/quality combination is not supported on the current Mac, VidPare disables it and explains why in the export sheet.

## Architecture

```text
SwiftUI Shell (views, timeline, export UI)
    |
VideoEngine (capability preflight, trim/export, progress)
    |
AVFoundation + VideoToolbox
```

## Local Development

### Build

```bash
swift build
```

### Run

```bash
.build/debug/VidPare
```

### Tests

```bash
swift test
```

### Cross-Architecture Checks (Apple Silicon Hosts)

Build x86_64 target:

```bash
swift build -c release --triple x86_64-apple-macosx14.0
```

Run x86_64 tests under Rosetta:

```bash
arch -x86_64 swift test --triple x86_64-apple-macosx14.0
```

## Release (Universal App + Notarized DMG)

Build universal app bundle:

```bash
VERSION=0.1.0 ./scripts/release/build-universal.sh
```

Sign and notarize app:

```bash
./scripts/release/sign-and-notarize.sh dist/VidPare.app
```

Package DMG:

```bash
VERSION=0.1.0 ./scripts/release/package-dmg.sh
```

Sign and notarize DMG:

```bash
./scripts/release/sign-and-notarize.sh dist/VidPare-0.1.0.dmg
```

Detailed release instructions are in [docs/release.md](docs/release.md).

## CI/CD

- PR/branch CI: `.github/workflows/ci.yml`
  - arm64 build + tests
  - x86_64 build
  - x86_64 tests under Rosetta
  - optional native Intel smoke job
- Tagged release pipeline: `.github/workflows/release.yml`
  - build universal app
  - sign/notarize app and DMG
  - publish DMG to GitHub Releases

## License

[MIT](LICENSE)

# VidPare

Native macOS video trimmer built with Swift, SwiftUI, and AVFoundation. Uses hardware-accelerated passthrough remux for near-instant, lossless trimming without re-encoding.

## Tech Stack

- **Platform**: macOS 14 (Sonoma)+
- **UI**: SwiftUI with `@Observable` (not `ObservableObject`)
- **Video**: AVFoundation / AVPlayer / AVAssetExportSession
- **Build system**: Swift Package (`Package.swift`) — no Xcode project file
- **Player**: `AVPlayer` + `AVPlayerLayer` in `NSViewRepresentable` (not SwiftUI's `VideoPlayer`)

## Code Style

- Do not add excessive comments within function bodies. Only add comments within function bodies to highlight details that may not be obvious.
- Use 2 spaces for indentation
- Run `swift-format -i <path>` to format the code in place
- Use `@Observable` macro (macOS 14+) instead of `ObservableObject` for state management

## Dependencies

```sh
brew install swift-format swiftlint
```

## Development Commands

- `swift build`
  Build the project from the command line.
- `swift build -c release`
  Build optimized release binary.
- `swift test`
  Run unit tests with Swift Testing/XCTest.
- `swift-format .`
  Format all code to match project style.
- `swiftlint`
  Run static analysis and style checks.
- Always Before pushing code to the remote, check it:
  - `swift build -v` - Build it
  - `swiftlint` - Lint it
  - `swift test` - Run unit tests
  - Where possible this should be done to avoid breaking the build!

### Product Website (`site/`)

- `cd site && npm ci && npm run dev` — local dev server
- `cd site && npm ci && npm run build` — production build (Cloudflare Pages)

## Architecture

```text
SwiftUI Shell (views, timeline, export UI)
    |
VideoEngine (AVAsset, AVMutableComposition, AVAssetExportSession)
    |
AVFoundation (Apple, hardware-accelerated via VideoToolbox)
```

No ffmpeg. No Electron. No WASM.

## Project Structure

```text
Sources/VidPare/
├── App/              # @main entry point, WindowGroup
├── Models/           # VideoDocument (AVAsset wrapper), TrimState (@Observable)
├── Views/            # ContentView, VideoPlayerView, TimelineView, PlayerControlsView, ExportSheet
├── Services/         # VideoEngine (trim/export), ThumbnailGenerator
└── Utilities/        # TimeFormatter and helpers
Tests/VidPareTests/   # Unit tests
site/                 # Cloudflare Pages product website
```

## Key Technical Conventions

- **Supported formats**: MP4, MOV, M4V only (no MKV/AVI/WebM)
- **Export modes**: Passthrough (default, fastest, lossless), High, Medium, Low
- **Passthrough**: preserves source codec; format picker disabled. Trim snaps to keyframes.
- **Re-encode presets** (High/Medium/Low): enable format picker (H.264 or HEVC)
- **HEVC + Passthrough**: auto-promotes to High unless source is already HEVC
- `AVAssetImageGenerator` should use `appliesPreferredTrackTransform = true` for rotated videos
- `AVAssetExportSession.progress` can be unreliable — poll at ~0.5s intervals
- Security-scoped resource access is reference-counted; block file loading during active exports

## Important Notes

- **Never commit** `.xcconfig` files or `.env` files containing API keys (e.g., Cloudflare, Apple notarization, Firebase, Stripe, third-party ML APIs). Add any local config files to `.gitignore`.
- **Storing secrets**:
  - **Local dev**: use environment variables, `.env` files (never committed), macOS Keychain, or [`envchain`](https://github.com/sorah/envchain) to inject secrets per-command. Example:
    ```sh
    envchain cloudflare sh -c 'OTEL_TRACES_EXPORTER= TF_VAR_cloudflare_api_token=$CLOUDFLARE_API_TOKEN TF_VAR_cloudflare_account_id=$CLOUDFLARE_ACCOUNT_ID terraform plan'
    ```
  - **CI**: use GitHub Actions secrets, HashiCorp Vault, or equivalent encrypted secret stores.
  - **Naming convention**: prefix keys with `VIDPARE_` (e.g., `VIDPARE_CLOUDFLARE_API_TOKEN`, `VIDPARE_APPLE_API_KEY`).
- The project uses a `Package.swift`-based layout — open the repo root in Xcode (`File > Open...`) for full IDE support including signing and entitlements.

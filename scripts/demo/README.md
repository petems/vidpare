# Demo Recording

Scripted screen recording of VidPare's trim workflow, used on the product website.

## Prerequisites

1. **Build VidPare**: `swift build` (or `make build`)
2. **Source video**: Place your demo clip at `scripts/demo/demo-source.mp4`
3. **macOS permissions** (grant to your terminal app):
   - System Settings > Privacy & Security > **Accessibility**
   - System Settings > Privacy & Security > **Screen & System Audio Recording**

## Usage

```sh
# From the repo root:
make demo
```

This runs `DemoRecorder record` which:

1. Launches VidPare with the source video auto-loaded via `VIDPARE_OPEN_FILE`
2. Captures the app window using ScreenCaptureKit (Retina, 30fps, H.264, no audio)
3. Runs the scripted UI scenario (playback → drag trim handles → export)
4. Post-processes the recording (trims head/tail, scales, re-encodes)
5. Outputs `site/public/demo.mp4` and `site/public/demo-poster.jpg`

## Options

```
DemoRecorder record [options]

  --source <path>   Source video file (required)
  --output <path>   Output MP4 path (default: site/public/demo.mp4)
  --poster <path>   Poster frame JPEG path (optional)
  --width <int>     Output width in pixels (default: 1920)
  --fps <int>       Recording frame rate (default: 30)
```

## What the demo shows

| Phase | Duration | Action |
|-------|----------|--------|
| Load | 0–2s | App launches with video pre-loaded, thumbnails visible |
| Playback | 2–5s | Video plays for ~3s, then pauses |
| Trim | 5–8s | Start handle dragged to ~29%, end handle dragged to ~50% |
| Export | 8–18s | Export sheet opens, save panel accepts, export completes |

## Re-recording

Run `make demo` again whenever a new release changes the UI. The output files in `site/public/` are committed to git so the website builds deterministically without needing the recorder.

## Limitations

- **Local only** — requires macOS permissions that can't be granted on CI runners (SIP)
- **Single monitor** — ScreenCaptureKit captures the window wherever it is; avoid overlapping windows
- **No audio** — the website plays the video muted

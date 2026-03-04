#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_BIN="${VIDPARE_BINARY:-$ROOT_DIR/.build/debug/VidPare}"
OUT_FILE="${1:-$ROOT_DIR/docs/screenshots/main-content-view.png}"

if [[ ! -x "$APP_BIN" ]]; then
  echo "Error: VidPare binary not found at '$APP_BIN'. Run 'swift build' first." >&2
  exit 1
fi

mkdir -p "$(dirname "$OUT_FILE")"

"$APP_BIN" >/tmp/vidpare-launch.log 2>&1 &
APP_PID=$!

cleanup() {
  if kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  pkill -f "\\.build/debug/VidPare" >/dev/null 2>&1 || true
}
trap cleanup EXIT

sleep 2

BOUNDS="$(
  APP_PID="$APP_PID" swift -e '
import Foundation
import CoreGraphics

let pid = Int32(ProcessInfo.processInfo.environment["APP_PID"]!)!
let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]

guard let windows = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else {
  exit(1)
}

for window in windows {
  guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int32, ownerPID == pid else {
    continue
  }
  guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else {
    continue
  }
  guard let bounds = window[kCGWindowBounds as String] as? [String: Any] else {
    continue
  }

  let x = Int((bounds["X"] as? Double) ?? 0)
  let y = Int((bounds["Y"] as? Double) ?? 0)
  let w = Int((bounds["Width"] as? Double) ?? 0)
  let h = Int((bounds["Height"] as? Double) ?? 0)

  if w > 0 && h > 0 {
    print("\(x),\(y),\(w),\(h)")
    exit(0)
  }
}

exit(2)
'
)"

if [[ -z "$BOUNDS" ]]; then
  echo "Error: Could not resolve VidPare window bounds for screenshot capture." >&2
  exit 1
fi

screencapture -x -R"$BOUNDS" "$OUT_FILE"
echo "Captured launch screenshot: $OUT_FILE"

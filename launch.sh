#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/build-app.sh"
APP_PATH="$SCRIPT_DIR/.build/app/ScanSong.app"
[[ -x "$APP_PATH/Contents/MacOS/ScanSong" ]] || { echo "Missing app executable: $APP_PATH" >&2; exit 1; }

pkill -TERM -x ScanSong 2>/dev/null || true
for _ in {1..20}; do
    pgrep -x ScanSong >/dev/null 2>&1 || break
    sleep 0.1
done
if pgrep -x ScanSong >/dev/null 2>&1; then
    echo "ScanSong did not terminate; refusing to launch over a stale process." >&2
    exit 1
fi

open -n "$APP_PATH"

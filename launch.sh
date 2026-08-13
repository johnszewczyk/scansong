#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
"$SCRIPT_DIR/build-app.sh"
APP_PATH="$SCRIPT_DIR/.build/app/MediaScanner.app"
[[ -x "$APP_PATH/Contents/MacOS/MediaScanner" ]] || { echo "Missing app executable: $APP_PATH" >&2; exit 1; }

pkill -TERM -x MediaScanner 2>/dev/null || true
for _ in {1..20}; do
    pgrep -x MediaScanner >/dev/null 2>&1 || break
    sleep 0.1
done
if pgrep -x MediaScanner >/dev/null 2>&1; then
    echo "MediaScanner did not terminate; refusing to launch over a stale process." >&2
    exit 1
fi

open -n "$APP_PATH"

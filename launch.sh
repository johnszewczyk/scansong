#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Retire the previous app before build-app.sh removes and recreates .build.
# Otherwise an active scan could lose access to its bundled inspectors while
# the new build is being assembled.
pkill -TERM -x ScanSong 2>/dev/null || true
# A scan may need a few seconds to finish its current checkpoint and reap
# decoder/archive children. Do not remove its bundle while that boundary is
# active.
for _ in {1..300}; do
    pgrep -x ScanSong >/dev/null 2>&1 || break
    sleep 0.1
done
if pgrep -x ScanSong >/dev/null 2>&1; then
    echo "ScanSong did not terminate; refusing to launch over a stale process." >&2
    exit 1
fi

"$SCRIPT_DIR/build-app.sh"
APP_PATH="$SCRIPT_DIR/.build/app/ScanSong.app"
[[ -x "$APP_PATH/Contents/MacOS/ScanSong" ]] || { echo "Missing app executable: $APP_PATH" >&2; exit 1; }

# Launch the exact freshly assembled executable. LaunchServices can retain an
# old bundle record after the framework closure is rewritten, so do not route
# this development launcher through `open`.
"$APP_PATH/Contents/MacOS/ScanSong" >/tmp/scansong-launch.log 2>&1 &
echo "Launched ScanSong"
echo "Log: /tmp/scansong-launch.log"

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODULE_CACHE="${TMPDIR:-/tmp}/mediascanner-module-cache"
APP_DIR="$SCRIPT_DIR/.build/app/MediaScanner.app"

mkdir -p "$MODULE_CACHE" "$APP_DIR/Contents/MacOS"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"

swift build --package-path "$SCRIPT_DIR" --disable-sandbox --configuration release --product MediaScanner
BIN_DIR="$(swift build --package-path "$SCRIPT_DIR" --disable-sandbox --configuration release --show-bin-path)"

install -m 755 "$BIN_DIR/MediaScanner" "$APP_DIR/Contents/MacOS/MediaScanner"
install -m 644 "$SCRIPT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"

echo "$APP_DIR"

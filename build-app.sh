#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
MODULE_CACHE="$BUILD_DIR/module-cache"
APP_DIR="$BUILD_DIR/app/MediaScanner.app"

rm -rf "$BUILD_DIR"
mkdir -p "$MODULE_CACHE" "$APP_DIR/Contents/MacOS"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"
export XDG_CACHE_HOME="$BUILD_DIR/cache"

swift build --package-path "$SCRIPT_DIR" --build-path "$BUILD_DIR" --disable-sandbox --configuration release --product MediaScanner
BIN_DIR="$BUILD_DIR/arm64-apple-macosx/release"
if [[ ! -x "$BIN_DIR/MediaScanner" ]]; then
    BIN_DIR="$(swift build --package-path "$SCRIPT_DIR" --build-path "$BUILD_DIR" --disable-sandbox --configuration release --show-bin-path)"
fi
[[ -x "$BIN_DIR/MediaScanner" ]] || { echo "Missing clean-built executable: $BIN_DIR/MediaScanner" >&2; exit 1; }

install -m 755 "$BIN_DIR/MediaScanner" "$APP_DIR/Contents/MacOS/MediaScanner"
install -m 644 "$SCRIPT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
codesign --force --sign - "$APP_DIR"

echo "$APP_DIR"

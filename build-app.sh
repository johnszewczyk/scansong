#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
MODULE_CACHE="$BUILD_DIR/module-cache"
APP_DIR="$BUILD_DIR/app/ScanSong.app"
VGMSTREAM_CLI_SOURCE="${MEDIASCANNER_VGMSTREAM_CLI:-$SCRIPT_DIR/../CocoaSpice/vendor/vgmstream/cli/vgmstream-cli}"
COCOASPICE_DIR="$SCRIPT_DIR/../CocoaSpice"
HIGHLY_COMPLETE_INSPECT_SOURCE="${MEDIASCANNER_HIGHLY_COMPLETE_INSPECT:-}"

rm -rf "$BUILD_DIR"
mkdir -p "$MODULE_CACHE" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"
export XDG_CACHE_HOME="$BUILD_DIR/cache"

swift build --package-path "$SCRIPT_DIR" --build-path "$BUILD_DIR" --disable-sandbox --configuration release --product ScanSong
BIN_DIR="$BUILD_DIR/arm64-apple-macosx/release"
if [[ ! -x "$BIN_DIR/ScanSong" ]]; then
    BIN_DIR="$(swift build --package-path "$SCRIPT_DIR" --build-path "$BUILD_DIR" --disable-sandbox --configuration release --show-bin-path)"
fi
[[ -x "$BIN_DIR/ScanSong" ]] || { echo "Missing clean-built executable: $BIN_DIR/ScanSong" >&2; exit 1; }

install -m 755 "$BIN_DIR/ScanSong" "$APP_DIR/Contents/MacOS/ScanSong"
install -m 644 "$SCRIPT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
[[ -x "$VGMSTREAM_CLI_SOURCE" ]] || { echo "Missing ScanSong vgmstream plugin: $VGMSTREAM_CLI_SOURCE" >&2; exit 1; }
install -m 755 "$VGMSTREAM_CLI_SOURCE" "$APP_DIR/Contents/Resources/vgmstream-cli"

if [[ -z "$HIGHLY_COMPLETE_INSPECT_SOURCE" ]]; then
    [[ -f "$COCOASPICE_DIR/.build/mgba/libmgba.a" ]] || "$COCOASPICE_DIR/scripts/build-mgba.sh"
    HIGHLY_COMPLETE_BIN_DIR="$(swift build --package-path "$COCOASPICE_DIR" --disable-sandbox --configuration release --product highly-complete-inspect --show-bin-path)"
    HIGHLY_COMPLETE_INSPECT_SOURCE="$HIGHLY_COMPLETE_BIN_DIR/highly-complete-inspect"
fi
[[ -x "$HIGHLY_COMPLETE_INSPECT_SOURCE" ]] || { echo "Missing ScanSong Highly Complete plugin: $HIGHLY_COMPLETE_INSPECT_SOURCE" >&2; exit 1; }
install -m 755 "$HIGHLY_COMPLETE_INSPECT_SOURCE" "$APP_DIR/Contents/Resources/highly-complete-inspect"

ICON_SOURCE=""
for candidate in "$SCRIPT_DIR/app-icon.png" "$SCRIPT_DIR/app-icon.jpg"; do
    if [[ -f "$candidate" ]]; then
        ICON_SOURCE="$candidate"
        break
    fi
done
if [[ -n "$ICON_SOURCE" ]]; then
    sips -s format png "$ICON_SOURCE" --out "$APP_DIR/Contents/Resources/app-icon.png" >/dev/null
fi
codesign --force --sign - "$APP_DIR"

echo "$APP_DIR"

#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/.build"
MODULE_CACHE="$BUILD_DIR/module-cache"
APP_DIR="$BUILD_DIR/app/ScanSong.app"
VGMBoy_DIR="$SCRIPT_DIR/../VGMBoy"
VGMBoy_SCANNER_PLUGIN_BUILDER="$VGMBoy_DIR/scripts/build-scanner-plugins.sh"

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
[[ -x "$VGMBoy_SCANNER_PLUGIN_BUILDER" ]] || { echo "Missing VGMBoy scanner plugin builder: $VGMBoy_SCANNER_PLUGIN_BUILDER" >&2; exit 1; }
"$VGMBoy_SCANNER_PLUGIN_BUILDER"
VGMSTREAM_CLI_SOURCE="${SCANSONG_VGMSTREAM_CLI:-$VGMBoy_DIR/.build/scanner-plugins/vgmstream-cli}"
[[ -x "$VGMSTREAM_CLI_SOURCE" ]] || { echo "Missing ScanSong vgmstream plugin: $VGMSTREAM_CLI_SOURCE" >&2; exit 1; }
install -m 755 "$VGMSTREAM_CLI_SOURCE" "$APP_DIR/Contents/Resources/vgmstream-cli"
MDX_INSPECT_SOURCE="${SCANSONG_MDX_INSPECT:-$VGMBoy_DIR/.build/scanner-plugins/vgmboy-mdx-inspect}"
[[ -x "$MDX_INSPECT_SOURCE" ]] || { echo "Missing ScanSong MDX plugin: $MDX_INSPECT_SOURCE" >&2; exit 1; }
install -m 755 "$MDX_INSPECT_SOURCE" "$APP_DIR/Contents/Resources/vgmboy-mdx-inspect"
AMIGA_INSPECT_SOURCE="${SCANSONG_AMIGA_INSPECT:-$VGMBoy_DIR/.build/scanner-plugins/vgmboy-amiga-inspect}"
[[ -x "$AMIGA_INSPECT_SOURCE" ]] || { echo "Missing ScanSong Amiga plugin: $AMIGA_INSPECT_SOURCE" >&2; exit 1; }
install -m 755 "$AMIGA_INSPECT_SOURCE" "$APP_DIR/Contents/Resources/vgmboy-amiga-inspect"
FRAMEWORKS_DIR="$APP_DIR/Contents/Frameworks"
mkdir -p "$FRAMEWORKS_DIR"
bundled_names=()
bundled_sources=()

has_bundled_name() {
    local candidate="$1"
    local existing
    for existing in "${bundled_names[@]:-}"; do
        [[ "$existing" == "$candidate" ]] && return 0
    done
    return 1
}

bundle_homebrew_dependency() {
    local source="$1"
    local name
    name="$(otool -D "$source" | tail -n 1 | xargs basename)"
    has_bundled_name "$name" && return 0

    bundled_names+=("$name")
    bundled_sources+=("$source")
    cp -X "$source" "$FRAMEWORKS_DIR/$name"

    local dependency
    while IFS= read -r dependency; do
        if [[ "$dependency" == /opt/homebrew/* && -f "$dependency" ]]; then
            bundle_homebrew_dependency "$dependency"
        fi
    done < <(otool -L "$source" | tail -n +2 | awk '{print $1}')
}

for plugin in "$APP_DIR/Contents/Resources/vgmstream-cli" "$APP_DIR/Contents/Resources/vgmboy-mdx-inspect" "$APP_DIR/Contents/Resources/vgmboy-amiga-inspect"; do
    while IFS= read -r dependency; do
        if [[ "$dependency" == /opt/homebrew/* && -f "$dependency" ]]; then
            bundle_homebrew_dependency "$dependency"
        fi
    done < <(otool -L "$plugin" | tail -n +2 | awk '{print $1}')
done

# UADE's dylib keeps libzakalwe.so as an @loader_path dependency rather than
# an absolute Homebrew path. Add that sibling explicitly so the Amiga helper
# remains runnable after the library is moved into the app bundle.
UADE_LIBRARY_ROOT="${SCANSONG_UADE_LIB_DIR:-/opt/homebrew/opt/uade/lib}"
if [[ -f "$UADE_LIBRARY_ROOT/libzakalwe.so" ]]; then
    bundle_homebrew_dependency "$UADE_LIBRARY_ROOT/libzakalwe.so"
fi

for index in "${!bundled_names[@]}"; do
    name="${bundled_names[$index]}"
    source="${bundled_sources[$index]}"
    destination="$FRAMEWORKS_DIR/$name"
    install_name_tool -id "@loader_path/$name" "$destination"
    while IFS= read -r dependency; do
        dependency_name="$(basename "$dependency")"
        if has_bundled_name "$dependency_name"; then
            install_name_tool -change "$dependency" "@loader_path/$dependency_name" "$destination"
        fi
    done < <(otool -L "$source" | tail -n +2 | awk '{print $1}')
done

for plugin in "$APP_DIR/Contents/Resources/vgmstream-cli" "$APP_DIR/Contents/Resources/vgmboy-mdx-inspect" "$APP_DIR/Contents/Resources/vgmboy-amiga-inspect"; do
    while IFS= read -r dependency; do
        dependency_name="$(basename "$dependency")"
        if has_bundled_name "$dependency_name"; then
            install_name_tool -change "$dependency" "@loader_path/../Frameworks/$dependency_name" "$plugin"
        fi
    done < <(otool -L "$plugin" | tail -n +2 | awk '{print $1}')
done

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
xattr -cr "$APP_DIR" 2>/dev/null || true
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"

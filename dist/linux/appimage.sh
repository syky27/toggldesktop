#!/usr/bin/env bash
#
# Build the Qt app and package it as Redtick-<ver>-x86_64.AppImage.
# Intended for Ubuntu (CI: ubuntu-22.04). Uses bundled POCO/jsoncpp/Qxt.
#
# Usage: dist/linux/appimage.sh [version]
#   version defaults to `git describe --tags` (leading v stripped), else 0.0.0
#
set -euo pipefail
cd "$(dirname "$0")/../.."          # repo root

APP_NAME="Redtick"
BIN_NAME="TogglDesktop"
BUILD_DIR="build-appimage"
APPDIR="$PWD/AppDir"
ICON_SRC="src/ui/linux/TogglDesktop/icons/256x256/toggldesktop.png"

VER="${1:-$(git describe --tags 2>/dev/null | sed -E 's/^v//; s/-([0-9]+)-.*/.\1/')}"
[ -z "$VER" ] && VER="0.0.0"
echo "==> Building $APP_NAME $VER AppImage"

# --- configure + build with bundled libs (no Toggl production servers / update
#     check). Skipped if the CI sanity-build already produced the binary. ---
BIN="$BUILD_DIR/src/ui/linux/TogglDesktop/$BIN_NAME"
if [ ! -x "$BIN" ]; then
    cmake -S . -B "$BUILD_DIR" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_INSTALL_PREFIX=/usr \
        -DUSE_BUNDLED_LIBRARIES=ON \
        -DTOGGL_BUILD_TESTS=OFF \
        -DTOGGL_VERSION="$VER"
    cmake --build "$BUILD_DIR" --target TogglDesktop -j"$(nproc)"
fi

# --- install into the AppDir (binary -> usr/bin, libTogglDesktopLibrary -> usr/lib,
#     cacert -> usr/share/toggldesktop; the app finds cacert via ../share/toggldesktop) ---
rm -rf "$APPDIR"
DESTDIR="$APPDIR" cmake --install "$BUILD_DIR"

# --- desktop entry + icon (rebranded to Redtick) ---
cat > "$APPDIR/$APP_NAME.desktop" <<DESK
[Desktop Entry]
Type=Application
Name=Redtick
GenericName=Redmine time tracker
Exec=$BIN_NAME
Icon=redtick
Categories=Office;ProjectManagement;
Terminal=false
DESK
cp "$ICON_SRC" "$APPDIR/redtick.png"

# --- fetch linuxdeploy + Qt plugin (cached in CI) ---
TOOLS="$PWD/.appimage-tools"
mkdir -p "$TOOLS"
fetch() { [ -x "$TOOLS/$1" ] || { curl -fsSL -o "$TOOLS/$1" "$2"; chmod +x "$TOOLS/$1"; }; }
fetch linuxdeploy-x86_64.AppImage          https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage
fetch linuxdeploy-plugin-qt-x86_64.AppImage https://github.com/linuxdeploy/linuxdeploy-plugin-qt/releases/download/continuous/linuxdeploy-plugin-qt-x86_64.AppImage

# --- bundle Qt + all NEEDED libs (incl. libXScrnSaver, pulled in via -lXss) and emit the AppImage ---
export OUTPUT="$APP_NAME-$VER-x86_64.AppImage"
export VERSION="$VER"
export QMAKE="${QMAKE:-qmake}"
"$TOOLS/linuxdeploy-x86_64.AppImage" \
    --appdir "$APPDIR" \
    --executable "$APPDIR/usr/bin/$BIN_NAME" \
    --desktop-file "$APPDIR/$APP_NAME.desktop" \
    --icon-file "$APPDIR/redtick.png" \
    --plugin qt \
    --output appimage

echo ""
echo "==> Built: $OUTPUT"

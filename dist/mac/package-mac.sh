#!/usr/bin/env bash
#
# Package the built Qt app into an unsigned Redtick.app and Redtick-<ver>.dmg.
#
# Assumes the binary is already built at
#   build/src/ui/linux/TogglDesktop/TogglDesktop
# (e.g. via ./run-mac.sh or the CMake recipe). Run from anywhere.
#
# Usage: dist/mac/package-mac.sh [version]
#   version defaults to `git describe --tags` (leading v stripped), else 0.0.0
#
set -euo pipefail
cd "$(dirname "$0")/../.."          # repo root

APP_NAME="Redtick"
BIN_NAME="TogglDesktop"             # internal binary/target name (unchanged)
BUNDLE_ID="cz.suma.redtick"
BUILD_DIR="build"
BIN="$BUILD_DIR/src/ui/linux/TogglDesktop/$BIN_NAME"
# Pre-padded macOS master: the raw icon fills the whole 1024 canvas, which makes
# the app tile render larger than other apps in cmd+Tab / the Dock. This master
# has the art scaled to Apple's ~824/1024 body with a 100px transparent margin.
# Regenerate from the raw icon if it changes:
#   python3 -c "from PIL import Image; c=Image.new('RGBA',(1024,1024),(0,0,0,0)); \
#     a=Image.open('src/ui/linux/TogglDesktop/icons/1024x1024/toggldesktop.png') \
#     .convert('RGBA').resize((824,824),Image.LANCZOS); c.paste(a,(100,100),a); \
#     c.save('dist/mac/redtick-icon-1024.png')"
ICON_PNG="dist/mac/redtick-icon-1024.png"
CACERT="src/ssl/cacert.pem"
QT_PREFIX="$(brew --prefix qt@5)"
DIST="$BUILD_DIR/pkg-mac"

# --- version ---
VER="${1:-$(git describe --tags 2>/dev/null | sed -E 's/^v//; s/-([0-9]+)-.*/.\1/')}"
[ -z "$VER" ] && VER="0.0.0"
echo "==> Packaging $APP_NAME $VER"

[ -x "$BIN" ] || { echo "ERROR: $BIN not found — build first (./run-mac.sh)"; exit 1; }

# --- assemble the .app skeleton ---
rm -rf "$DIST"
APP="$DIST/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/$BIN_NAME"
cp "$CACERT" "$APP/Contents/MacOS/cacert.pem"     # app looks for cacert.pem next to its binary

# --- icon -> .icns ---
ICONSET="$DIST/$APP_NAME.iconset"
mkdir -p "$ICONSET"
for s in 16 32 64 128 256 512; do
    sips -z "$s" "$s"           "$ICON_PNG" --out "$ICONSET/icon_${s}x${s}.png"    >/dev/null
    d=$((s * 2))
    sips -z "$d" "$d"           "$ICON_PNG" --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/$APP_NAME.icns"

# --- Info.plist ---
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>$APP_NAME</string>
    <key>CFBundleDisplayName</key><string>$APP_NAME</string>
    <key>CFBundleExecutable</key><string>$BIN_NAME</string>
    <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
    <key>CFBundleIconFile</key><string>$APP_NAME</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VER</string>
    <key>CFBundleVersion</key><string>$VER</string>
    <key>LSMinimumSystemVersion</key><string>11.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

# --- bundle Qt frameworks/plugins (fixes the main binary's Qt deps) ---
echo "==> macdeployqt"
"$QT_PREFIX/bin/macdeployqt" "$APP" -verbose=1

# --- add plugins macdeployqt skips. It bundles QtSvg + the SVG icon engine
#     (iconengines/libqsvgicon) but NOT the SVG *image reader*
#     (imageformats/libqsvg), so Qt can't rasterize `background:url(*.svg)` in a
#     stylesheet -> the group expand/collapse glyphs fail with "Could not create
#     pixmap from :/images/group_icon_*.svg". Copy the reader in and repoint its
#     Homebrew Qt-framework refs at the bundled frameworks (same rewrite
#     macdeployqt applied to libqsvgicon). ---
NEEDED_PLUGINS=("imageformats/libqsvg.dylib")
for rel in "${NEEDED_PLUGINS[@]}"; do
    dst="$APP/Contents/PlugIns/$rel"
    [ -f "$dst" ] && continue
    src="$QT_PREFIX/plugins/$rel"
    [ -f "$src" ] || { echo "    WARN: $src not found — skipping"; continue; }
    echo "==> adding plugin $rel (macdeployqt skipped it)"
    mkdir -p "$(dirname "$dst")"
    cp "$src" "$dst"; chmod u+w "$dst"
    deps=$(otool -L "$dst" | awk 'NR>1{print $1}' | grep -E '/opt/homebrew.*\.framework/' || true)
    [ -n "$deps" ] && while IFS= read -r dep; do
        fw=$(echo "$dep" | sed -E 's#.*/([A-Za-z0-9]+\.framework/.*)$#\1#')
        install_name_tool -change "$dep" "@executable_path/../Frameworks/$fw" "$dst"
    done <<< "$deps"
done

# macdeployqt already bundles Qt frameworks/plugins AND the non-Qt dependent
# dylibs (POCO/OpenSSL/jsoncpp + libTogglDesktopLibrary/libQxt/libBugsnag) into
# Contents/Frameworks and rewrites their load commands to @rpath/@executable_path.
# BUT it leaves the original Homebrew LC_RPATH entries inside some of them — e.g.
# libTogglDesktopLibrary.dylib keeps `/opt/homebrew/opt/poco/lib`. Since the POCO
# libs reference each other as `@rpath/libPoco*.dylib`, that stray rpath gives dyld
# a SECOND place to resolve them, so it loads BOTH the bundled and the Homebrew
# POCO. Two copies => two Poco::Data::SessionFactory singletons => the SQLite
# connector registers in one while SetDBPath queries the other => it throws =>
# the app SIGSEGVs at startup (in Context::displayError). So strip every
# Homebrew/usr-local rpath from EVERY Mach-O in the bundle; afterwards `@rpath`
# resolves only via the main binary's @executable_path/../Frameworks.
echo "==> stripping Homebrew rpaths from all bundled Mach-O files"
while IFS= read -r f; do
    rps=$(otool -l "$f" 2>/dev/null \
        | awk '/^ +cmd /{r=($2=="LC_RPATH")} r&&$1=="path"{print $2}' \
        | grep -E '/opt/homebrew|/usr/local' || true)
    [ -n "$rps" ] || continue
    while IFS= read -r rp; do
        install_name_tool -delete_rpath "$rp" "$f" 2>/dev/null \
            && echo "    $(basename "$f"): - $rp"
    done <<< "$rps"
done < <(find "$APP/Contents/Frameworks" "$APP/Contents/PlugIns" "$APP/Contents/MacOS" -type f 2>/dev/null)

# --- ad-hoc sign (so the bundle has a stable code identity; still "unsigned"
#     for Gatekeeper — first launch needs right-click -> Open) ---
codesign --force --deep --sign - "$APP" || echo "(ad-hoc sign skipped)"

# --- build the .dmg (drag-to-Applications) ---
echo "==> hdiutil"
STAGE="$DIST/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"
DMG="$DIST/$APP_NAME-$VER.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null

echo ""
echo "==> Built: $DMG"
echo "    Self-containment check — scanning every Mach-O for Homebrew/usr-local"
echo "    LC_LOAD_DYLIB deps and LC_RPATHs (LC_ID_DYLIB self-names are ignored):"
LEAK=0
while IFS= read -r f; do
    bad=$(otool -l "$f" 2>/dev/null | awk '
        /^ +cmd /{ if($2=="LC_LOAD_DYLIB"){w=1;k="dep"} else if($2=="LC_RPATH"){w=1;k="rpath"} else {w=0}; next }
        w && ($1=="name"||$1=="path"){print k" "$2; w=0}
    ' | grep -E '/opt/homebrew|/usr/local' || true)
    if [ -n "$bad" ]; then
        LEAK=1
        echo "    !! $(basename "$f")"
        echo "$bad" | sed 's/^/        /'
    fi
done < <(find "$APP/Contents/Frameworks" "$APP/Contents/PlugIns" "$APP/Contents/MacOS" -type f 2>/dev/null)
if [ "$LEAK" = 0 ]; then
    echo "    OK — fully self-contained (no Homebrew paths in any bundled Mach-O)"
else
    echo "    !! Homebrew paths remain — the .dmg would crash on a clean Mac. Failing."
    exit 1
fi

#!/usr/bin/env bash
# Cross-compiles the core's native deps (OpenSSL 3, jsoncpp, Poco) for iOS into a
# per-SDK prefix consumed by app/native/CMakeLists.txt via -DREDTICK_DEPS_PREFIX.
# Part of FP-12. Runs on a macOS host with Xcode (e.g. GitHub macos-14 runner).
#
# Usage:
#   ./build-deps-ios.sh iphoneos        arm64           # device
#   ./build-deps-ios.sh iphonesimulator arm64 x86_64    # simulator (fat)
#
# Output: $OUT/<sdk>/ with lib/ + include/ for OpenSSL, jsoncpp, Poco (static).
set -euo pipefail

SDK="${1:?usage: build-deps-ios.sh <iphoneos|iphonesimulator> <arch...>}"; shift
ARCHS="${*:-arm64}"
MIN_IOS="${MIN_IOS:-13.0}"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-$HERE/.deps-build}"
OUT="${OUT:-$HERE/.deps-prefix}"
PREFIX="$OUT/$SDK"
SRC="$WORK/src"
mkdir -p "$PREFIX" "$SRC"

SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"
# CMake arch list (semicolon-separated) and OpenSSL primary arch/target.
CMAKE_ARCHS="$(echo "$ARCHS" | tr ' ' ';')"
PRIMARY_ARCH="$(echo "$ARCHS" | awk '{print $1}')"
if [ "$SDK" = "iphoneos" ]; then OSSL_TARGET=ios64-cross; else OSSL_TARGET=iossimulator-xcrun; fi

CMAKE_COMMON=(
  -DCMAKE_SYSTEM_NAME=iOS
  -DCMAKE_OSX_SYSROOT="$SDK"
  -DCMAKE_OSX_ARCHITECTURES="$CMAKE_ARCHS"
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_IOS"
  -DCMAKE_INSTALL_PREFIX="$PREFIX"
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
  -DCMAKE_IOS_INSTALL_COMBINED=OFF
)

fetch() { local url="$1" dir="$2"
  [ -d "$SRC/$dir" ] || { echo ">> $url"; curl -fsSL "$url" -o "$SRC/$dir.tgz"; tar -xzf "$SRC/$dir.tgz" -C "$SRC"; }; }

# --- OpenSSL 3 (device arch only; simulator builds primary arch) ---
OSSL_VER="${OSSL_VER:-3.0.14}"
fetch "https://github.com/openssl/openssl/releases/download/openssl-$OSSL_VER/openssl-$OSSL_VER.tar.gz" "openssl-$OSSL_VER"
( cd "$SRC/openssl-$OSSL_VER"
  export CROSS_TOP="$(dirname "$(dirname "$SYSROOT")")"
  export CROSS_SDK="$(basename "$SYSROOT")"
  export CC="$(xcrun -find clang)"
  ./Configure "$OSSL_TARGET" "-arch $PRIMARY_ARCH -mios-version-min=$MIN_IOS" \
    no-shared no-tests no-asm --prefix="$PREFIX" --openssldir="$PREFIX/ssl"
  make -j"$JOBS"
  make install_sw )

# --- jsoncpp ---
JSON_VER="${JSON_VER:-1.9.5}"
fetch "https://github.com/open-source-parsers/jsoncpp/archive/refs/tags/$JSON_VER.tar.gz" "jsoncpp-$JSON_VER"
cmake -S "$SRC/jsoncpp-$JSON_VER" -B "$WORK/jsoncpp-$SDK" "${CMAKE_COMMON[@]}" \
  -DJSONCPP_WITH_TESTS=OFF -DJSONCPP_WITH_POST_BUILD_UNITTEST=OFF -DBUILD_OBJECT_LIBS=OFF
cmake --build "$WORK/jsoncpp-$SDK" --target install -j"$JOBS"

# --- Poco ---
POCO_VER="${POCO_VER:-1.12.4}"
fetch "https://github.com/pocoproject/poco/archive/refs/tags/poco-$POCO_VER-release.tar.gz" "poco-poco-$POCO_VER-release"
cmake -S "$SRC/poco-poco-$POCO_VER-release" -B "$WORK/poco-$SDK" "${CMAKE_COMMON[@]}" \
  -DOPENSSL_ROOT_DIR="$PREFIX" \
  -DOPENSSL_USE_STATIC_LIBS=TRUE \
  -DOPENSSL_CRYPTO_LIBRARY="$PREFIX/lib/libcrypto.a" \
  -DOPENSSL_SSL_LIBRARY="$PREFIX/lib/libssl.a" \
  -DOPENSSL_INCLUDE_DIR="$PREFIX/include" \
  -DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
  -DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
  -DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH \
  -DENABLE_DATA_SQLITE=ON -DENABLE_CRYPTO=ON -DENABLE_NETSSL=ON \
  -DENABLE_NET=ON -DENABLE_UTIL=ON -DENABLE_JSON=OFF -DENABLE_XML=OFF \
  -DENABLE_MONGODB=OFF -DENABLE_REDIS=OFF -DENABLE_ZIP=OFF \
  -DENABLE_DATA_MYSQL=OFF -DENABLE_DATA_ODBC=OFF \
  -DENABLE_PAGECOMPILER=OFF -DENABLE_PAGECOMPILER_FILE2PAGE=OFF \
  -DENABLE_ACTIVERECORD=OFF -DENABLE_ACTIVERECORD_COMPILER=OFF -DENABLE_TESTS=OFF
cmake --build "$WORK/poco-$SDK" --target install -j"$JOBS"

echo "== done: iOS dependency prefix at $PREFIX =="

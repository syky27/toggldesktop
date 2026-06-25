#!/usr/bin/env bash
# Cross-compiles the C core's native dependencies (OpenSSL 3, jsoncpp, Poco) for
# Android, producing a per-ABI prefix that app/native/CMakeLists.txt consumes via
# -DREDTICK_DEPS_PREFIX. Part of FP-11.
#
# Requirements:
#   ANDROID_NDK_HOME  -> path to an installed NDK (r25+)
#   ANDROID_API       -> min API level (default 24)
#
# Usage:
#   ANDROID_NDK_HOME=~/Android/Sdk/ndk/27.0.12077973 ./build-deps.sh arm64-v8a
#   (repeat per ABI: arm64-v8a armeabi-v7a x86_64)
#
# Output: $OUT/<abi>/ with lib/ + include/ for OpenSSL, jsoncpp, Poco (static).
#
# NOTE: This script could not be executed in the build environment used to author
# the port — the NDK is only distributed from dl.google.com, which the network
# policy blocks. It is provided ready-to-run wherever the NDK is reachable.
set -euo pipefail

ABI="${1:?usage: build-deps.sh <abi>  (arm64-v8a|armeabi-v7a|x86_64|x86)}"
API="${ANDROID_API:-24}"
NDK="${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to an installed NDK}"
JOBS="$(nproc 2>/dev/null || echo 4)"

HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-$HERE/.deps-build}"
OUT="${OUT:-$HERE/.deps-prefix}"
PREFIX="$OUT/$ABI"
SRC="$WORK/src"
mkdir -p "$PREFIX" "$SRC"

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/linux-x86_64"
export PATH="$TOOLCHAIN/bin:$PATH"

# Map ABI -> OpenSSL target + clang triple prefix.
case "$ABI" in
  arm64-v8a)   OSSL_TARGET=android-arm64; TRIPLE=aarch64-linux-android ;;
  armeabi-v7a) OSSL_TARGET=android-arm;   TRIPLE=armv7a-linux-androideabi ;;
  x86_64)      OSSL_TARGET=android-x86_64; TRIPLE=x86_64-linux-android ;;
  x86)         OSSL_TARGET=android-x86;   TRIPLE=i686-linux-android ;;
  *) echo "unknown ABI $ABI" >&2; exit 2 ;;
esac

CMAKE_COMMON=(
  -DCMAKE_TOOLCHAIN_FILE="$NDK/build/cmake/android.toolchain.cmake"
  -DANDROID_ABI="$ABI"
  -DANDROID_PLATFORM="android-$API"
  -DCMAKE_INSTALL_PREFIX="$PREFIX"
  -DCMAKE_BUILD_TYPE=Release
  -DBUILD_SHARED_LIBS=OFF
)

fetch() { # url sha-dir
  local url="$1" dir="$2"
  [ -d "$SRC/$dir" ] || { echo ">> fetching $url"; curl -fsSL "$url" -o "$SRC/$dir.tgz"; tar -xzf "$SRC/$dir.tgz" -C "$SRC"; }
}

# --- OpenSSL 3 ---
OSSL_VER="${OSSL_VER:-3.0.14}"
fetch "https://github.com/openssl/openssl/releases/download/openssl-$OSSL_VER/openssl-$OSSL_VER.tar.gz" "openssl-$OSSL_VER"
( cd "$SRC/openssl-$OSSL_VER"
  export ANDROID_NDK_ROOT="$NDK"
  ./Configure "$OSSL_TARGET" -D__ANDROID_API__="$API" no-shared no-tests \
    --prefix="$PREFIX" --openssldir="$PREFIX/ssl"
  make -j"$JOBS"
  make install_sw )

# --- jsoncpp ---
JSON_VER="${JSON_VER:-1.9.5}"
fetch "https://github.com/open-source-parsers/jsoncpp/archive/refs/tags/$JSON_VER.tar.gz" "jsoncpp-$JSON_VER"
cmake -S "$SRC/jsoncpp-$JSON_VER" -B "$WORK/jsoncpp-$ABI" "${CMAKE_COMMON[@]}" \
  -DJSONCPP_WITH_TESTS=OFF -DJSONCPP_WITH_POST_BUILD_UNITTEST=OFF \
  -DBUILD_OBJECT_LIBS=OFF
cmake --build "$WORK/jsoncpp-$ABI" --target install -j"$JOBS"

# --- Poco (Crypto, Data/SQLite, NetSSL, Foundation, Util, Net) ---
POCO_VER="${POCO_VER:-1.12.4}"
fetch "https://github.com/pocoproject/poco/archive/refs/tags/poco-$POCO_VER-release.tar.gz" "poco-poco-$POCO_VER-release"
cmake -S "$SRC/poco-poco-$POCO_VER-release" -B "$WORK/poco-$ABI" "${CMAKE_COMMON[@]}" \
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
  -DENABLE_ACTIVERECORD=OFF -DENABLE_ACTIVERECORD_COMPILER=OFF \
  -DPOCO_UNBUNDLED=OFF -DENABLE_TESTS=OFF
cmake --build "$WORK/poco-$ABI" --target install -j"$JOBS"

echo "== done: dependency prefix at $PREFIX =="

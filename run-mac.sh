#!/usr/bin/env bash
#
# Build and run the Redmine time tracker (Toggl Desktop fork) on macOS.
#
#   ./run-mac.sh
#
# Installs any missing Homebrew build dependencies, configures and builds the
# Qt app, then launches it. Log in with your Redmine URL + personal API key.
#
set -euo pipefail

# Always operate from the repository root (this script's directory).
cd "$(dirname "$0")"

if ! command -v brew >/dev/null 2>&1; then
    echo "Homebrew is required. Install it from https://brew.sh and re-run." >&2
    exit 1
fi

echo "==> Checking build dependencies..."
for pkg in cmake pkg-config qt@5 openssl@3 poco jsoncpp; do
    if brew list --versions "$pkg" >/dev/null 2>&1; then
        echo "    ok:        $pkg"
    else
        echo "    installing: $pkg"
        brew install "$pkg"
    fi
done

QT_PREFIX="$(brew --prefix qt@5)"
SSL_PREFIX="$(brew --prefix openssl@3)"
POCO_PREFIX="$(brew --prefix poco)"
JSONCPP_PREFIX="$(brew --prefix jsoncpp)"

echo "==> Configuring (CMake)..."
cmake -S . -B build \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_PREFIX_PATH="${QT_PREFIX};${POCO_PREFIX};${JSONCPP_PREFIX}" \
    -DOPENSSL_ROOT_DIR="${SSL_PREFIX}" \
    -DPOCO_INCLUDE_DIRS="${POCO_PREFIX}/include" \
    -DJSONCPP_INCLUDE_DIRS="${JSONCPP_PREFIX}/include"

JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
echo "==> Building (using ${JOBS} cores; the first build takes a few minutes)..."
cmake --build build --target TogglDesktop -j"${JOBS}"

APP="build/src/ui/linux/TogglDesktop/TogglDesktop"
if [[ ! -x "${APP}" ]]; then
    echo "Build did not produce ${APP}" >&2
    exit 1
fi

echo ""
echo "==> Launching the app."
echo "    Log in with your Redmine URL (e.g. https://your-redmine.example.com)"
echo "    and your personal Redmine API key."
echo ""
# The app finds cacert.pem next to its own binary, so cwd does not matter.
exec "./${APP}" "$@"

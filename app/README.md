# Redtick — Flutter app

One Flutter codebase (iOS, Android, macOS, Windows, Linux) over the existing C++
core (`../src`), bound via `dart:ffi`. See `../docs/flutter-port/` for the full
plan, ADR, and platform-feature notes.

## Architecture

```
../src                         C++ core (unchanged) → libTogglDesktopLibrary
app/native/CMakeLists.txt      builds the core as a shared lib per platform (FP-10/60)
app/native/bridge.{h,c}        thread-safe deep-copy shim for struct callbacks (FP-22b)
app/lib/src/native/            FFI: bindings, CoreService (streams), rt bridge, cacert
app/lib/src/models/            Dart models mirroring the core view structs
app/lib/src/state/             Riverpod providers + per-platform DB path
app/lib/src/ui/                screens (login, timer, list, editor, calendar, settings)
app/lib/src/platform/          notifications + platform-feature hooks (Phase 5)
```

The C core pushes data through `toggl_on_*` callbacks → `CoreService` exposes them
as Dart streams → Riverpod providers → widgets. Actions call `toggl_*` functions.

## Prerequisites

- Flutter stable (3.44+).
- Core build deps:
  - **Linux:** `libpoco-dev libjsoncpp-dev libssl-dev libxmu-dev libx11-dev cmake ninja-build libgtk-3-dev`
  - **macOS/iOS:** Poco/OpenSSL/jsoncpp via the xcframework toolchain (FP-12).
  - **Android:** NDK cross-build of the core + deps (FP-11).
  - **Windows:** Poco/OpenSSL/jsoncpp + the core DLL (FP-64).

## Build & run

```bash
# 1. (desktop) build + run — the linux CMake builds & bundles the core automatically
flutter pub get
flutter run -d linux            # or macos / windows

# 2. regenerate the full FFI bindings from the C header
dart run ffigen --config ffigen.yaml

# 3. analyze + test
flutter analyze
flutter test                    # ffi_smoke_test skips unless REDTICK_CORE_LIB is set

# 4. run the real FFI test against a built core
cmake -S native -B ../build/native -DCMAKE_BUILD_TYPE=Release && cmake --build ../build/native -j
REDTICK_CORE_LIB=../build/native/libTogglDesktopLibrary.so flutter test test/ffi_smoke_test.dart
```

## Notes

- TLS: a CA bundle (`assets/cacert.pem`) is materialized at runtime and passed to
  the core (`toggl_set_cacert_path`).
- The core must be built **without** `UNICODE` so `char_t == char` (UTF-8) on all
  platforms, including Windows (see ADR-0001).

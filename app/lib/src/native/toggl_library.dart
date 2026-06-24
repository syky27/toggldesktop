import 'dart:ffi' as ffi;
import 'dart:io' show Platform;

/// Loads the native `libTogglDesktopLibrary` (the existing C++ core) for the
/// current platform. The per-platform artifact is produced by the core build
/// (issues FP-10/11/12) and bundled by the Flutter platform build (FP-60).
///
/// Library name by platform:
///   * Android — `libTogglDesktopLibrary.so` (in the APK, found by name)
///   * iOS/macOS — symbols are statically linked into the app process when an
///     xcframework is used, so we open the process itself.
///   * Linux — `libTogglDesktopLibrary.so` next to the executable
///   * Windows — `TogglDesktopLibrary.dll`
class TogglLibrary {
  static ffi.DynamicLibrary open() {
    if (Platform.isAndroid) {
      return ffi.DynamicLibrary.open('libTogglDesktopLibrary.so');
    }
    if (Platform.isLinux) {
      return ffi.DynamicLibrary.open('libTogglDesktopLibrary.so');
    }
    if (Platform.isWindows) {
      return ffi.DynamicLibrary.open('TogglDesktopLibrary.dll');
    }
    if (Platform.isIOS || Platform.isMacOS) {
      // Statically linked into the runner via the xcframework.
      return ffi.DynamicLibrary.process();
    }
    throw UnsupportedError(
        'Unsupported platform: ${Platform.operatingSystem}');
  }
}

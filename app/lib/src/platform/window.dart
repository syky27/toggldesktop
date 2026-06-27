import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'idle_log.dart';

/// Desktop window control (idle bring-to-front). Raises redtick's own window via
/// the `redtick/window` platform channel (implemented in each desktop Runner) so
/// the user sees the "You've been idle" prompt when they return. No-op where
/// unsupported, so callers stay platform-agnostic. Mirrors [IdleDetector].
class AppWindow {
  static const _ch = MethodChannel('redtick/window');

  static bool get supported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  /// Best-effort raise-to-foreground. Fire-and-forget: never throws, so callers
  /// (e.g. the idle prompt) needn't guard it. The OS may refuse focus theft
  /// (Win32 background restriction, Wayland) — that's logged, not surfaced.
  static Future<void> foreground() async {
    if (!supported) return;
    try {
      final raised = await _ch.invokeMethod<bool>('foreground');
      idleLog('native window.foreground -> raised=$raised');
    } catch (e, st) {
      // Mirror IdleDetector.seconds(): a MissingPluginException or any channel
      // error must be observable, not silent.
      idleLog('native window.foreground FAILED: $e\n$st');
    }
  }
}

import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Desktop idle detection (design §3.9). Reports seconds since the last user
/// input via the `redtick/idle` platform channel (implemented in the macOS
/// Runner). Returns 0 where unsupported, so callers can stay platform-agnostic.
class IdleDetector {
  static const _ch = MethodChannel('redtick/idle');

  static bool get supported =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  static Future<double> seconds() async {
    if (!supported) return 0;
    try {
      final v = await _ch.invokeMethod<double>('idleSeconds');
      return v ?? 0;
    } catch (_) {
      return 0;
    }
  }
}

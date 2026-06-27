import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import 'idle_log.dart';

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
      idleLog('native idleSeconds -> $v');
      return v ?? 0;
    } catch (e, st) {
      // Previously swallowed silently, which made a MissingPluginException (or
      // any channel error) look identical to "user isn't idle". Surface it.
      idleLog('native idleSeconds FAILED: $e\n$st');
      return 0;
    }
  }
}

import 'package:flutter/foundation.dart';

/// Idle-chain diagnostics (design §3.9). Off by default so shipped builds stay
/// silent; turn on with `--dart-define=REDTICK_IDLE_DEBUG=true`.
///
/// Uses `debugPrint` (the repo's house style — cf. `notifications.dart`,
/// `live_timer.dart`) so the trace prints directly in the `flutter run`
/// terminal as `[redtick.idle] ...` lines. The native side logs the same tag
/// via `NSLog`, which also reaches Console.app / `log stream` for release
/// builds (where `debugPrint` is compiled out).
///
/// Why this exists: the idle prompt only misbehaves in real desktop runs, and
/// both the native handler and the Dart channel call used to swallow failures
/// to 0 with no signal. This makes the whole chain observable.
const bool kIdleDebug =
    bool.fromEnvironment('REDTICK_IDLE_DEBUG', defaultValue: false);

void idleLog(String message) {
  if (!kIdleDebug) return;
  debugPrint('[redtick.idle] $message');
}

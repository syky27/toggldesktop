import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

/// Presents reminder/pomodoro notices from the core (FP-54).
///
/// The default implementation shows in-app material banners/snackbars (handled
/// by the UI listener). On desktop and mobile, OS-level notifications should be
/// delivered by swapping in a [NotificationPresenter] backed by
/// `flutter_local_notifications` — see docs/flutter-port/platform-features.md.
/// This indirection keeps the core wiring testable without a platform plugin.
abstract class NotificationPresenter {
  void show(String title, String body);

  /// The default presenter: logs (and the UI also shows an in-app banner).
  factory NotificationPresenter.defaultFor() {
    if (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isWindows ||
        Platform.isLinux) {
      return _LoggingPresenter();
    }
    return _LoggingPresenter();
  }
}

class _LoggingPresenter implements NotificationPresenter {
  @override
  void show(String title, String body) {
    debugPrint('[notification] $title — $body');
  }
}

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Presents reminder/pomodoro notices from the app (FP-54) and the
/// "running but not tracking" reminder.
///
/// The real presenter ([_LocalNotificationPresenter]) delivers an OS-level
/// notification via `flutter_local_notifications`, so it surfaces in the corner
/// even when the window is focused (foreground presentation is enabled). [show]
/// reports whether it was delivered to an authorized notification center; the UI
/// shows an in-app banner only as a *fallback* when it wasn't (permission denied,
/// or an unsupported platform such as Windows). Any plugin failure degrades
/// silently to logging — never crashes the app.
abstract class NotificationPresenter {
  /// Warm up the plugin and request OS permission up front (so the prompt appears
  /// proactively, not on the first reminder). Safe to call repeatedly.
  Future<void> init();

  /// Deliver an OS notification. Returns `true` if it was delivered to an
  /// authorized notification center, `false` if the caller should fall back to
  /// in-app UI (denied / unsupported / error).
  Future<bool> show(String title, String body);

  /// The default presenter for the running platform.
  factory NotificationPresenter.defaultFor() {
    // flutter_local_notifications supports these platforms; Windows + others
    // fall back to logging (the in-app banner remains the visible cue).
    if (Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS ||
        Platform.isLinux) {
      return _LocalNotificationPresenter();
    }
    return _LoggingPresenter();
  }
}

/// Delivers real OS notifications. Initialises lazily (or eagerly via [init]),
/// requests permission on macOS/iOS and remembers the grant, and falls back to
/// logging on any error.
class _LocalNotificationPresenter implements NotificationPresenter {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _inited = false;
  bool _failed = false;
  bool _authorized = false;
  int _id = 0;

  // iOS/macOS: present the banner even while the app is frontmost (macOS
  // otherwise suppresses notifications from the active app — so only the in-app
  // banner would show). presentAlert covers older OSes; presentBanner/List the
  // newer ones.
  static const _darwin = DarwinNotificationDetails(
    presentAlert: true,
    presentBanner: true,
    presentList: true,
  );

  Future<void> _ensureInit() async {
    if (_inited || _failed) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // We request permission explicitly below (to capture the grant), so don't
    // also auto-request during initialize.
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const linux = LinuxInitializationSettings(defaultActionName: 'Open');
    const settings = InitializationSettings(
      android: android,
      iOS: darwin,
      macOS: darwin,
      linux: linux,
    );
    try {
      await _plugin.initialize(settings: settings);
      _authorized = await _requestPermission();
      _inited = true;
    } catch (e) {
      _failed = true;
      debugPrint('[notification:init-failed] $e');
    }
  }

  /// Returns whether notifications are authorized. Non-Darwin platforms don't
  /// gate local notifications behind a runtime prompt here, so treat as granted.
  Future<bool> _requestPermission() async {
    if (Platform.isMacOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                  MacOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: false, sound: false) ??
          false;
    }
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                  IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, badge: false, sound: false) ??
          false;
    }
    if (Platform.isAndroid) {
      // Android 13+ (API 33) requires a runtime grant. On older Android the
      // resolver returns null → treat as granted. A denial degrades gracefully:
      // show() returns false and the UI falls back to the in-app banner.
      final granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      return granted ?? true;
    }
    return true;
  }

  @override
  Future<void> init() => _ensureInit();

  @override
  Future<bool> show(String title, String body) async {
    try {
      await _ensureInit();
      if (_failed || !_authorized) return false;
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'redtick_reminders',
          'Reminders',
          channelDescription: 'Idle and "track your time" reminders',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: _darwin,
        macOS: _darwin,
        linux: LinuxNotificationDetails(),
      );
      await _plugin.show(
        id: _id++,
        title: title,
        body: body,
        notificationDetails: details,
      );
      return true;
    } catch (e) {
      _failed = true; // stop retrying; rely on the in-app banner
      debugPrint('[notification:fallback] $title — $body ($e)');
      return false;
    }
  }
}

class _LoggingPresenter implements NotificationPresenter {
  @override
  Future<void> init() async {}

  @override
  Future<bool> show(String title, String body) async {
    debugPrint('[notification] $title — $body');
    return false; // no OS notification — caller shows the in-app fallback
  }
}

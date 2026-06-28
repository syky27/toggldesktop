import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'live_timer.dart';

/// Notification id of the running-timer ongoing notification. Shared with the
/// background-reconcile isolate (`background_reconcile.dart`) so it can tear the
/// surface down without an instance of the controller.
const int kRunningNotificationId = 1001;

/// Android [LiveTimerController]: the running-timer glance surface (design §6),
/// realised as an **ongoing notification** in the status bar / shade.
///
/// Like the iOS Live Activity, the surface renders its own ticking clock —
/// here via Android's notification chronometer (`usesChronometer: true` +
/// `when: startedAt`), so we only push on lifecycle changes (start /
/// issue-change / stop), never every second.
///
/// First cut uses a plain ongoing notification (no foreground service): light,
/// no extra permissions beyond POST_NOTIFICATIONS (Android 13+, already
/// requested by the reminders presenter and re-requested here idempotently).
/// If the OS later reclaims it while backgrounded, escalate to a true
/// foreground service. Best-effort throughout — any failure (permission denied,
/// plugin error) is swallowed so the timer itself never breaks.
class AndroidLiveTimerController implements LiveTimerController {
  AndroidLiveTimerController();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inited = false;
  bool _failed = false;

  /// Stable id so a refresh replaces (not stacks) the surface and [end] cancels
  /// exactly it. Distinct from the reminders presenter's auto-incrementing ids.
  static const int _notificationId = kRunningNotificationId;
  static const String _channelId = 'redtick_running';

  /// The entry currently shown (null = nothing). Skips a redundant re-show for
  /// the same entry; replaced when the running issue/aggregate changes.
  String? _activeGuid;

  Future<void> _ensureInit() async {
    if (_inited || _failed) return;
    try {
      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const settings = InitializationSettings(android: android);
      await _plugin.initialize(settings: settings);
      // Idempotent: the reminders presenter usually prompts first, but ask here
      // too so the surface works even if reminders were never triggered.
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _inited = true;
    } catch (e) {
      _failed = true;
      debugPrint('[live] Android live-timer init failed: $e');
    }
  }

  @override
  void start(LiveTimerInfo info) {
    if (!Platform.isAndroid) return;
    _start(info); // fire-and-forget behind the synchronous interface
  }

  Future<void> _start(LiveTimerInfo info) async {
    try {
      await _ensureInit();
      if (_failed) return;
      if (_activeGuid == info.guid) return; // already showing this exact entry

      final title = info.issueRef.isEmpty
          ? (info.description.isEmpty ? 'Tracking time' : info.description)
          : '${info.issueRef} ${info.description}'.trim();
      final body = info.project.isEmpty ? null : info.project;

      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Running timer',
          channelDescription: 'Shows the currently running timer',
          // Low importance: visible + persistent, but silent (no sound/vibration
          // on every refresh).
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true, // can't be swiped away while the timer runs
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: true,
          when: info.startedAt.millisecondsSinceEpoch,
          usesChronometer: true, // Android ticks elapsed from `when` itself
          category: AndroidNotificationCategory.stopwatch,
        ),
      );
      await _plugin.show(
        id: _notificationId,
        title: title,
        body: body,
        notificationDetails: details,
      );
      _activeGuid = info.guid;
    } catch (e) {
      _activeGuid = null;
      debugPrint('[live] Android live-timer start failed: $e');
    }
  }

  @override
  void end() {
    if (!Platform.isAndroid) return;
    _end();
  }

  Future<void> _end() async {
    _activeGuid = null;
    try {
      await _plugin.cancel(id: _notificationId);
    } catch (e) {
      debugPrint('[live] Android live-timer end failed: $e');
    }
  }
}

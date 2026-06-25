import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:live_activities/live_activities.dart';

import 'live_timer.dart';

/// iOS [LiveTimerController] backed by ActivityKit via the `live_activities`
/// plugin (the running-timer glance surface: lock screen + Dynamic Island).
///
/// The SwiftUI widget (`ios/RedtickLiveActivity`) reads `issue` / `description`
/// / `project` / `startedAt` from the shared App Group and renders its own
/// ticking clock from `startedAt`, so we only push on lifecycle changes (start
/// / issue-change / stop) — never every second. The activity is **local only**
/// (no push updates) and best-effort: any failure (Live Activities disabled,
/// old OS, no entitlement) is swallowed so the timer itself never breaks.
class IosLiveActivityController implements LiveTimerController {
  IosLiveActivityController();

  /// Must match the App Group enabled on both the Runner and the
  /// `RedtickLiveActivity` extension targets in Xcode.
  static const _appGroupId = 'group.cz.syky.redtick';

  final LiveActivities _plugin = LiveActivities();
  bool _inited = false;

  /// The running entry currently shown (null = nothing shown). Lets us skip a
  /// redundant restart for the same entry and replace it when the issue changes.
  String? _activeGuid;

  Future<void> _ensureInit() async {
    if (_inited) return;
    await _plugin.init(appGroupId: _appGroupId);
    _inited = true;
  }

  @override
  void start(LiveTimerInfo info) {
    if (!Platform.isIOS) return;
    _start(info); // fire-and-forget behind the synchronous interface
  }

  Future<void> _start(LiveTimerInfo info) async {
    try {
      await _ensureInit();
      if (!await _plugin.areActivitiesEnabled()) return;
      // Already showing this exact entry — nothing to do.
      if (_activeGuid == info.guid) return;

      // Exactly one running-timer activity at a time: clear ours *and* any
      // activity orphaned by a previous app session (we never run two), then
      // start fresh. This is what makes an issue-change replace cleanly and
      // prevents duplicates after a force-quit-while-running + relaunch.
      await _plugin.endAllActivities();

      final data = <String, dynamic>{
        'issue': info.issueRef,
        'description': info.description,
        'project': info.project,
        // Epoch seconds; the widget builds Date(timeIntervalSince1970:) and
        // ticks an up-counting Text(timerInterval:) from it.
        'startedAt': info.startedAt.millisecondsSinceEpoch ~/ 1000,
      };
      await _plugin.createActivity(
        info.guid,
        data,
        // Local glance only — no server, so don't request a push token (which
        // would require the Push Notifications capability).
        iOSEnableRemoteUpdates: false,
        // If the app is explicitly terminated, drop the activity; a relaunch
        // with the timer still running recreates it.
        removeWhenAppIsKilled: true,
      );
      _activeGuid = info.guid;
    } catch (e) {
      _activeGuid = null;
      debugPrint('[live] iOS Live Activity start failed: $e');
    }
  }

  @override
  void end() {
    if (!Platform.isIOS) return;
    _end();
  }

  Future<void> _end() async {
    _activeGuid = null;
    try {
      // We only ever own the single running-timer activity, so ending all is
      // equivalent and also sweeps any orphan.
      await _plugin.endAllActivities();
    } catch (e) {
      debugPrint('[live] iOS Live Activity end failed: $e');
    }
  }
}

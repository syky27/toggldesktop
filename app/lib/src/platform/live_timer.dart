import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../models/time_entry.dart';

/// Drives the platform "live" glance surfaces from the running-timer state
/// (design §6): an **iOS Live Activity** (ActivityKit / WidgetKit) and an
/// **Android Live Update** (foreground-service ongoing notification).
///
/// The surfaces render their own ticking clock from `startedAt`, so we only push
/// on lifecycle changes (start / issue-change / stop), never every second.
///
/// This is the seam the design calls for: the real platform implementations
/// (an iOS SwiftUI widget extension + an Android foreground notification) slot
/// in behind this interface. The default is a logging no-op, so desktop and the
/// (not-yet-built) mobile targets stay functional. See
/// `docs/flutter-port/LIVE_SURFACES.md` for what each platform still needs.
abstract class LiveTimerController {
  /// A timer started (or the running issue changed) — show/refresh the surface.
  void start(LiveTimerInfo info);

  /// The timer stopped — tear the surface down.
  void end();

  factory LiveTimerController.defaultFor() {
    // Hook real implementations here once their native targets exist:
    //   if (Platform.isIOS) return IosLiveActivityController();
    //   if (Platform.isAndroid) return AndroidLiveUpdateController();
    return _LoggingLiveTimer();
  }
}

/// The minimal payload a live surface needs (it computes elapsed from [startedAt]).
class LiveTimerInfo {
  const LiveTimerInfo({
    required this.guid,
    required this.description,
    required this.issueRef,
    required this.project,
    required this.startedAt,
  });

  final String guid;
  final String description;
  final String issueRef; // e.g. "#4821"
  final String project;
  final DateTime startedAt;

  static LiveTimerInfo fromEntry(TimeEntry e) {
    final tl = e.taskLabel;
    final ref = tl.isEmpty
        ? ''
        : (tl.contains(':') ? tl.substring(0, tl.indexOf(':')) : tl);
    return LiveTimerInfo(
      guid: e.guid,
      description: e.description,
      issueRef: ref,
      project: e.projectLabel,
      startedAt:
          DateTime.fromMillisecondsSinceEpoch(e.started * 1000).toLocal(),
    );
  }
}

class _LoggingLiveTimer implements LiveTimerController {
  @override
  void start(LiveTimerInfo info) {
    if (Platform.isIOS || Platform.isAndroid) {
      debugPrint('[live] start ${info.issueRef} ${info.description} '
          '(native surface not yet wired)');
    } else {
      debugPrint('[live] start ${info.issueRef} ${info.description}');
    }
  }

  @override
  void end() => debugPrint('[live] end');
}

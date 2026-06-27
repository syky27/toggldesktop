import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/providers.dart';
import '../../state/reminder_notice.dart';
import '../../state/reminder_settings.dart';

/// Wraps the app shell and, while **no** timer is running, periodically nags the
/// user to track their time — an OS notification (when available) plus an in-app
/// banner. Mirrors the Qt app's "remind me to track time" feature. The gating
/// (interval, weekdays, active-hours window) lives in [shouldRemind]; this
/// widget just drives the clock and surfaces the notice. Design §3.9 / screen
/// 10 ("IDLE & REMINDERS").
///
/// **Desktop-only.** On iOS/Android the OS keeps the app alive in the
/// background, so a "you're not tracking" nudge there is just noise; the watcher
/// stays inert on mobile (still passing [child] through unchanged).
class ReminderWatcher extends ConsumerStatefulWidget {
  const ReminderWatcher({
    super.key,
    required this.child,
    this.clock = DateTime.now,
    this.isDesktopOverride,
  });
  final Widget child;

  /// Wall-clock, injectable so tests can drive the throttle/idle gating
  /// deterministically (the periodic timer itself is driven by `tester.pump`).
  final DateTime Function() clock;

  /// Test seam for the desktop/mobile decision. Production leaves this null and
  /// the platform is read from `dart:io` in [initState].
  final bool? isDesktopOverride;

  @override
  ConsumerState<ReminderWatcher> createState() => _ReminderWatcherState();
}

class _ReminderWatcherState extends ConsumerState<ReminderWatcher> {
  Timer? _timer;

  /// Anchor for the "every N minutes" throttle. Initialised to now so the first
  /// reminder is a full interval away, and re-anchored whenever a timer runs so
  /// the countdown starts fresh once tracking stops.
  DateTime? _lastReminder;

  /// Consecutive ticks observing "no timer running". Defence-in-depth on top of
  /// the reconcile fix: even if the timer state flaps to null for a single tick
  /// (server read-miss), we only nag once idle is sustained across
  /// [_idleTicksToFire] ticks (~60s). Reset whenever a timer is observed.
  int _idleTicks = 0;
  static const int _idleTicksToFire = 2;

  @override
  void initState() {
    super.initState();
    final isDesktop = widget.isDesktopOverride ??
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux);
    // Desktop-only: a phone keeps the app alive in the background, so a
    // "you're not tracking" notification there is just noise. Desktop apps can
    // be fully quit, where the nudge is useful. Stay inert on mobile.
    if (!isDesktop) return;
    _lastReminder = widget.clock();
    // Request OS notification permission up front so the reminder surfaces as a
    // system notification (not just the in-app fallback) when it first fires.
    ref.read(notificationPresenterProvider).init();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _tick() async {
    if (!mounted) return;
    final settings = ref.read(reminderSettingsProvider);
    // Synchronous snapshot, NOT timerStateProvider: that StreamProvider is never
    // watched, so a cold ref.read returns AsyncLoading (null) and the reminder
    // would nag even while a timer runs. Same root cause as the idle prompt.
    final running = ref.read(coreServiceProvider).currentTimer;
    final isRunning = running != null && running.isRunning;
    final now = widget.clock();

    if (isRunning) {
      _idleTicks = 0;
      _lastReminder = now; // re-anchor: count the gap from when tracking stops
      return;
    }

    // Absorb a single transient flap to null: only consider a reminder once
    // idle has been observed across [_idleTicksToFire] consecutive ticks.
    _idleTicks++;
    if (_idleTicks < _idleTicksToFire) return;

    if (!shouldRemind(
      now: now,
      lastReminder: _lastReminder,
      running: false,
      s: settings,
    )) {
      return;
    }

    _lastReminder = now;
    const title = 'Redtick';
    const body = 'No timer running — track your time?';
    // Persistent in-app banner — stays until a timer starts (no auto-dismiss).
    ref.read(reminderNoticeProvider.notifier).show(body);
    // Plus the OS notification as an extra cue (surfaces even when the window is
    // unfocused). Fire-and-forget; failures degrade silently to logging.
    unawaited(ref.read(notificationPresenterProvider).show(title, body));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

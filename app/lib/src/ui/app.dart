import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/time_entry.dart';
import '../platform/live_timer.dart';
import '../state/multi_task_settings.dart';
import '../state/providers.dart';
import '../state/theme_mode.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme.dart';
import 'widgets/idle_prompt.dart';
import 'widgets/reminder_watcher.dart';

/// Root widget. Routes between the login screen and the main shell based on the
/// core's login state, and wires global error toasts. Implements FP-40 (shell).
class RedtickApp extends ConsumerWidget {
  const RedtickApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Redtick',
      debugShowCheckedModeBanner: false,
      theme: RedtickTheme.light(),
      darkTheme: RedtickTheme.dark(),
      themeMode: ref.watch(themeModeProvider),
      home: const _AuthGate(),
    );
  }
}

final _liveTimerProvider =
    Provider<LiveTimerController>((ref) => LiveTimerController.defaultFor());

/// A stable signature of the live-surface state so the listener only pushes on a
/// meaningful change. Empty = nothing running; `one:<guid>` = a single timer;
/// `agg:<count>:<earliestEpoch>` = several at once.
String _liveSurfaceKey(List<TimeEntry>? entries) {
  final list =
      (entries ?? const <TimeEntry>[]).where((e) => e.isRunning).toList();
  if (list.isEmpty) return '';
  if (list.length == 1) return 'one:${list.first.guid}';
  var earliest = list.first.started;
  for (final e in list) {
    if (e.started < earliest) earliest = e.started;
  }
  return 'agg:${list.length}:$earliest';
}

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  void _toast(BuildContext context, String message) {
    if (message.isEmpty) return;
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Surface core errors as snackbars globally.
    ref.listen(errorsProvider, (_, next) {
      final err = next.asData?.value;
      if (err != null) _toast(context, err.message);
    });

    // Reminder + pomodoro notices: in-app banner + platform notification (FP-54).
    final presenter = ref.read(notificationPresenterProvider);
    ref.listen(remindersProvider, (_, next) {
      final n = next.asData?.value;
      if (n != null) {
        presenter.show(n.title, n.body);
        _toast(context, '${n.title} ${n.body}'.trim());
      }
    });
    ref.listen(pomodoroProvider, (_, next) {
      final n = next.asData?.value;
      if (n != null) {
        presenter.show(n.title, n.body);
        _toast(context, '${n.title} ${n.body}'.trim());
      }
    });

    // Live surfaces (iOS Live Activity / Android Live Update): one timer shows
    // that entry; several show an aggregate "N timers running" summary. Keyed so
    // we only push on a meaningful change (count / which entry / earliest start)
    // — not every second (the surface ticks itself).
    final live = ref.read(_liveTimerProvider);
    ref.listen(runningEntriesProvider, (prev, next) {
      final prevKey = _liveSurfaceKey(prev?.asData?.value);
      final list = (next.asData?.value ?? const <TimeEntry>[])
          .where((e) => e.isRunning)
          .toList();
      if (_liveSurfaceKey(next.asData?.value) == prevKey) return;
      if (list.isEmpty) {
        live.end();
      } else if (list.length == 1) {
        live.start(LiveTimerInfo.fromEntry(list.first));
      } else {
        var earliest = list.first.started;
        for (final e in list) {
          if (e.started < earliest) earliest = e.started;
        }
        live.start(LiveTimerInfo.aggregate(
          count: list.length,
          earliestStart:
              DateTime.fromMillisecondsSinceEpoch(earliest * 1000),
        ));
      }
    });

    // Switching concurrent tracking off while several timers run collapses to
    // the most recently started one (the rest are stopped).
    ref.listen(multiTaskSettingsProvider, (prev, next) {
      if ((prev?.allowConcurrent ?? false) && !next.allowConcurrent) {
        ref.read(coreServiceProvider).collapseRunningToMostRecent();
      }
    });

    final loggedIn = ref.watch(isLoggedInProvider);
    return loggedIn
        ? const IdleWatcher(
            child: ReminderWatcher(
              child: _LifecycleRefresher(child: HomeShell()),
            ),
          )
        : const LoginScreen();
  }
}

/// Reconciles with Redmine when the app returns to the foreground, so a timer
/// stopped/started on another device is reflected immediately (the periodic
/// poll covers the steady state). See `RedmineService.refresh`.
class _LifecycleRefresher extends ConsumerStatefulWidget {
  const _LifecycleRefresher({required this.child});
  final Widget child;

  @override
  ConsumerState<_LifecycleRefresher> createState() =>
      _LifecycleRefresherState();
}

class _LifecycleRefresherState extends ConsumerState<_LifecycleRefresher>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(coreServiceProvider).refresh(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

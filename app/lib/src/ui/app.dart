import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/live_timer.dart';
import '../platform/notifications.dart';
import '../state/providers.dart';
import '../state/theme_mode.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'theme.dart';
import 'widgets/idle_prompt.dart';

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

final _notificationPresenterProvider =
    Provider<NotificationPresenter>((ref) => NotificationPresenter.defaultFor());

final _liveTimerProvider =
    Provider<LiveTimerController>((ref) => LiveTimerController.defaultFor());

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
    final presenter = ref.read(_notificationPresenterProvider);
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

    // Live surfaces (iOS Live Activity / Android Live Update): start on a new
    // running entry, end on stop — never per second (the surface ticks itself).
    final live = ref.read(_liveTimerProvider);
    ref.listen(timerStateProvider, (prev, next) {
      final running = next.asData?.value;
      final was = prev?.asData?.value;
      final isRunning = running != null && running.isRunning;
      final wasRunning = was != null && was.isRunning;
      if (isRunning && (!wasRunning || was.guid != running.guid)) {
        live.start(LiveTimerInfo.fromEntry(running));
      } else if (!isRunning && wasRunning) {
        live.end();
      }
    });

    final loggedIn = ref.watch(isLoggedInProvider);
    return loggedIn
        ? const IdleWatcher(child: HomeShell())
        : const LoginScreen();
  }
}

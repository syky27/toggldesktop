import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/redmine_service.dart';
import '../models/time_entry.dart';

/// Holds the live [RedmineService] (the pure-Dart backend that replaced the FFI
/// `CoreService`). Overridden in `main()` after `RedmineService.create()`.
/// The provider name is kept (`coreServiceProvider`) so the UI is untouched.
final coreServiceProvider = Provider<RedmineService>(
  (ref) => throw UnimplementedError(
      'coreServiceProvider must be overridden in main() with the created RedmineService'),
);

/// The current time-entry list pushed by the core (`on_time_entry_list`).
final timeEntriesProvider = StreamProvider<List<TimeEntry>>((ref) async* {
  final core = ref.watch(coreServiceProvider);
  // Replay the last list (startup on_time_entry_list fires before subscription).
  final last = core.currentTimeEntries;
  if (last != null) yield last;
  yield* core.timeEntries;
});

/// Whether the "load more" button should be shown.
final showLoadMoreProvider = StreamProvider<bool>(
  (ref) => ref.watch(coreServiceProvider).showLoadMore,
);

/// The running entry (or null when stopped).
final timerStateProvider = StreamProvider<TimeEntry?>(
  (ref) => ref.watch(coreServiceProvider).timerState,
);

/// Login transitions. Seeds the auth gate in the UI.
final loginStateProvider = StreamProvider<LoginEvent>((ref) async* {
  final core = ref.watch(coreServiceProvider);
  // Replay the last login transition: the startup on_login fires during
  // CoreService.start (before this provider subscribes); a plain broadcast
  // stream would drop it, so a cached session would not auto-log-in.
  final last = core.currentLogin;
  if (last != null) yield last;
  yield* core.loginState;
});

/// Errors surfaced by the core (wire to a global snackbar).
final errorsProvider = StreamProvider<CoreError>(
  (ref) => ref.watch(coreServiceProvider).errors,
);

/// Online/offline/backend-down state.
final onlineStateProvider = StreamProvider<int>(
  (ref) => ref.watch(coreServiceProvider).onlineState,
);

/// Reminder notices (FP-54).
final remindersProvider = StreamProvider<Notice>(
  (ref) => ref.watch(coreServiceProvider).reminders,
);

/// Pomodoro notices (FP-54).
final pomodoroProvider = StreamProvider<Notice>(
  (ref) => ref.watch(coreServiceProvider).pomodoro,
);

/// Idle-detection notices (FP-52, desktop).
final idleProvider = StreamProvider<IdleNotice>(
  (ref) => ref.watch(coreServiceProvider).idle,
);

/// Convenience: whether the user is currently logged in.
final isLoggedInProvider = Provider<bool>((ref) {
  final login = ref.watch(loginStateProvider).asData?.value;
  return login?.loggedIn ?? false;
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/time_entry.dart';
import '../native/core_service.dart';

/// Holds the live [CoreService]. Overridden in `main()` after the async core
/// init completes (see `main.dart`). Implements FP-24.
final coreServiceProvider = Provider<CoreService>(
  (ref) => throw UnimplementedError(
      'coreServiceProvider must be overridden in main() with the started CoreService'),
);

/// The current time-entry list pushed by the core (`on_time_entry_list`).
final timeEntriesProvider = StreamProvider<List<TimeEntry>>(
  (ref) => ref.watch(coreServiceProvider).timeEntries,
);

/// Whether the "load more" button should be shown.
final showLoadMoreProvider = StreamProvider<bool>(
  (ref) => ref.watch(coreServiceProvider).showLoadMore,
);

/// The running entry (or null when stopped).
final timerStateProvider = StreamProvider<TimeEntry?>(
  (ref) => ref.watch(coreServiceProvider).timerState,
);

/// Login transitions. Seeds the auth gate in the UI.
final loginStateProvider = StreamProvider<LoginEvent>(
  (ref) => ref.watch(coreServiceProvider).loginState,
);

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

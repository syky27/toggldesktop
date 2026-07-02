import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/http_log.dart';
import '../data/redmine_service.dart';
import '../models/time_entry.dart';
import '../platform/deep_link.dart';
import '../platform/notifications.dart';

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

/// The running entry (or null when stopped). Carries the primary
/// (most-recently-started) timer when several run concurrently.
///
/// NOTE: this is only useful to widgets that `watch`/`listen` it (it stays warm
/// then). Imperative pollers that merely `ref.read` it — the idle prompt and the
/// "not tracking" reminder — must read [RedmineService.currentTimer] directly
/// instead: a never-watched `StreamProvider` is not kept subscribed, so a cold
/// `ref.read` returns `AsyncLoading` (null) even while a timer runs.
final timerStateProvider = StreamProvider<TimeEntry?>(
  (ref) => ref.watch(coreServiceProvider).timerState,
);

/// All currently-running entries (most-recently-started last), driving the
/// stacked top bar. Empty when nothing is tracking. Replays the last list for
/// late subscribers (the bar subscribes after startup events).
final runningEntriesProvider = StreamProvider<List<TimeEntry>>((ref) async* {
  final core = ref.watch(coreServiceProvider);
  yield core.currentRunningEntries;
  yield* core.runningEntries;
});

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

/// The toggl_* custom-field config (send toggle + the three ids). Drives the
/// Settings section and the simple-mode UI gating (Calendar menu item +
/// per-entry start/stop timestamps). Replays the current value for late
/// subscribers.
final customFieldConfigProvider =
    StreamProvider<CustomFieldConfig>((ref) async* {
  final core = ref.watch(coreServiceProvider);
  yield core.currentCustomFieldConfig;
  yield* core.customFieldConfig;
});

/// One-shot notice emitted when a write rejection auto-disables custom fields
/// (wire to a one-time dialog).
final customFieldsAutoDisabledProvider = StreamProvider<CustomFieldNotice>(
  (ref) => ref.watch(coreServiceProvider).customFieldsAutoDisabled,
);

/// Timestamp of the last successful sync (drives the desktop "Synced · Ns ago"
/// indicator). Replays the last value for late subscribers.
final syncStateProvider = StreamProvider<DateTime?>((ref) async* {
  final core = ref.watch(coreServiceProvider);
  final last = core.lastSyncedAt;
  if (last != null) yield last;
  yield* core.syncEvents;
});

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

/// Incoming `redtick://start` deep links from the browser extension: the
/// cold-start launch link (replayed by app_links to the first subscriber) then
/// warm links while running. Desktop-only (empty elsewhere). Parsed +
/// dispatched to the service in `app.dart`.
final deepLinkUriProvider = StreamProvider<Uri>(
  (ref) => DeepLinks.uriStream(),
);

/// One-shot outcomes of handling a deep link (started / confirm-concurrent /
/// already-running / error). Wired to a toast + confirm dialog in `app.dart`.
final deepLinkNoticesProvider = StreamProvider<DeepLinkNotice>(
  (ref) => ref.watch(coreServiceProvider).deepLinkNotices,
);

/// Convenience: whether the user is currently logged in.
final isLoggedInProvider = Provider<bool>((ref) {
  final login = ref.watch(loginStateProvider).asData?.value;
  return login?.loggedIn ?? false;
});

/// OS-notification presenter (real banners via flutter_local_notifications,
/// logging fallback). Shared by `_AuthGate` and the reminder watcher.
final notificationPresenterProvider =
    Provider<NotificationPresenter>((ref) => NotificationPresenter.defaultFor());

/// The live HTTP logger (records all Redmine + GitHub traffic when enabled).
/// Overridden in `main()` with the instance created there (so the same object
/// is shared by every `RedmineApiClient` and the settings toggle). Mirrors the
/// override pattern of [coreServiceProvider].
final httpLoggerProvider = Provider<HttpLogger>(
  (ref) => throw UnimplementedError(
      'httpLoggerProvider must be overridden in main() with the created HttpLogger'),
);

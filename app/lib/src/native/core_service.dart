import 'dart:async';
import 'dart:ffi' as ffi;
import 'package:ffi/ffi.dart';

import '../models/time_entry.dart';
import 'toggl_bindings.dart';
import 'toggl_library.dart';

/// Idiomatic Dart facade over the C core (`src/toggl_api.h`).
///
/// Responsibilities:
///  * own the `void* context` lifecycle (FP-21);
///  * marshal Dart values to/from the C ABI (UTF-8 strings, `bool_t` ints);
///  * bridge the `toggl_on_*` push-callbacks into broadcast [Stream]s (FP-22);
///  * walk the linked-list view structs into [TimeEntry] models (FP-23).
///
/// `toggl_ui_start` (called by [start]) requires the CA-cert path to be set and
/// EVERY mandatory display callback to be registered (Context::VerifyCallbacks).
/// We therefore register real handlers for the streams the UI consumes and
/// no-op handlers for the rest (autocomplete, selects, reminders, …) until those
/// features are built out.
///
/// Threading: callbacks are wired with [ffi.NativeCallable.listener] so the core
/// may invoke them from its own threads; the Dart handlers then run on this
/// isolate's event loop. See ADR-0001 for the struct-lifetime caveat and the
/// planned C bridge shim that deep-copies struct payloads.
class CoreService {
  CoreService._(this._bindings);

  final TogglBindings _bindings;
  ffi.Pointer<ffi.Void> _ctx = ffi.nullptr;

  // Retained NativeCallables — kept alive for the context's lifetime, closed in
  // [dispose].
  final List<ffi.NativeCallable<dynamic>> _callbacks = [];

  final _timeEntries = StreamController<List<TimeEntry>>.broadcast();
  final _showLoadMore = StreamController<bool>.broadcast();
  final _timerState = StreamController<TimeEntry?>.broadcast();
  final _loginState = StreamController<LoginEvent>.broadcast();
  final _errors = StreamController<CoreError>.broadcast();
  final _onlineState = StreamController<int>.broadcast();

  Stream<List<TimeEntry>> get timeEntries => _timeEntries.stream;
  Stream<bool> get showLoadMore => _showLoadMore.stream;
  Stream<TimeEntry?> get timerState => _timerState.stream;
  Stream<LoginEvent> get loginState => _loginState.stream;
  Stream<CoreError> get errors => _errors.stream;
  Stream<int> get onlineState => _onlineState.stream;

  /// Loads the native library, creates the core context, registers callbacks
  /// and starts the core.
  ///
  /// [dbPath] must be writable (FP-25). [cacertPath] must point at a PEM CA
  /// bundle (required by StartEvents); bundle one as an asset on mobile, or use
  /// the system bundle on desktop. [baseUrl] is the Redmine backend.
  static CoreService start({
    required String appName,
    required String appVersion,
    required String dbPath,
    required String cacertPath,
    String? logPath,
    String? baseUrl,
    ffi.DynamicLibrary? library,
  }) {
    final bindings = TogglBindings(library ?? TogglLibrary.open());
    final service = CoreService._(bindings);
    service._init(appName, appVersion, dbPath, cacertPath, logPath, baseUrl);
    return service;
  }

  void _init(String appName, String appVersion, String dbPath,
      String cacertPath, String? logPath, String? baseUrl) {
    _withUtf8(appName, (n) {
      _withUtf8(appVersion, (v) {
        _ctx = _bindings.contextInit(n, v);
      });
    });
    if (_ctx == ffi.nullptr) {
      throw StateError('toggl_context_init returned null');
    }

    if (logPath != null) {
      _withUtf8(logPath, (p) => _bindings.setLogPath(p));
    }
    _withUtf8(cacertPath, (p) => _bindings.setCacertPath(_ctx, p));
    if (baseUrl != null && baseUrl.isNotEmpty) {
      _withUtf8(baseUrl, (p) => _bindings.setBaseUrl(_ctx, p));
    }
    _withUtf8(dbPath, (p) => _bindings.setDbPath(_ctx, p));

    _registerCallbacks();

    if (_bindings.uiStart(_ctx) == 0) {
      throw StateError('toggl_ui_start failed (check CA cert + callbacks)');
    }
  }

  void _reg<T extends Function>(String symbol, ffi.NativeCallable<T> cb) {
    _bindings.onRegister(symbol)(_ctx, cb.nativeFunction.cast());
    _callbacks.add(cb);
  }

  void _registerCallbacks() {
    // --- real handlers (streams the UI consumes) ---
    _reg<DisplayTimeEntryListNative>(
        'toggl_on_time_entry_list',
        ffi.NativeCallable<DisplayTimeEntryListNative>.listener(
            _onTimeEntryList));
    _reg<DisplayTimerStateNative>('toggl_on_timer_state',
        ffi.NativeCallable<DisplayTimerStateNative>.listener(_onTimerState));
    _reg<DisplayLoginNative>('toggl_on_login',
        ffi.NativeCallable<DisplayLoginNative>.listener(_onLogin));
    _reg<DisplayErrorNative>('toggl_on_error',
        ffi.NativeCallable<DisplayErrorNative>.listener(_onError));
    _reg<DisplayOnlineStateNative>('toggl_on_online_state',
        ffi.NativeCallable<DisplayOnlineStateNative>.listener(_onOnlineState));

    // --- mandatory callbacks not yet surfaced in the UI: no-op stubs so
    //     Context::VerifyCallbacks passes (see findMissingCallbacks). ---
    _reg<DisplayAppNative>('toggl_on_show_app',
        ffi.NativeCallable<DisplayAppNative>.listener((int _) {}));
    _reg<DisplayUrlNative>('toggl_on_url',
        ffi.NativeCallable<DisplayUrlNative>.listener((ffi.Pointer<Utf8> _) {}));
    _reg<DisplayString2Native>(
        'toggl_on_reminder',
        ffi.NativeCallable<DisplayString2Native>.listener(
            (ffi.Pointer<Utf8> _, ffi.Pointer<Utf8> _) {}));
    _reg<DisplayString2Native>(
        'toggl_on_pomodoro',
        ffi.NativeCallable<DisplayString2Native>.listener(
            (ffi.Pointer<Utf8> _, ffi.Pointer<Utf8> _) {}));
    _reg<DisplayString2Native>(
        'toggl_on_pomodoro_break',
        ffi.NativeCallable<DisplayString2Native>.listener(
            (ffi.Pointer<Utf8> _, ffi.Pointer<Utf8> _) {}));
    _reg<DisplaySettingsNative>(
        'toggl_on_settings',
        ffi.NativeCallable<DisplaySettingsNative>.listener(
            (int _, ffi.Pointer<ffi.Void> _) {}));
    _reg<DisplayEditorNative>(
        'toggl_on_time_entry_editor',
        ffi.NativeCallable<DisplayEditorNative>.listener(
            (int _, ffi.Pointer<TogglTimeEntryView> _, ffi.Pointer<Utf8> _) {}));
    _reg<DisplayIdleNative>(
        'toggl_on_idle_notification',
        ffi.NativeCallable<DisplayIdleNative>.listener((
          ffi.Pointer<Utf8> _,
          ffi.Pointer<Utf8> _,
          ffi.Pointer<Utf8> _,
          int _,
          ffi.Pointer<Utf8> _,
          ffi.Pointer<Utf8> _,
          ffi.Pointer<Utf8> _,
          ffi.Pointer<Utf8> _,
        ) {}));
    for (final symbol in const [
      'toggl_on_time_entry_autocomplete',
      'toggl_on_mini_timer_autocomplete',
      'toggl_on_project_autocomplete',
      'toggl_on_workspace_select',
      'toggl_on_client_select',
      'toggl_on_tags',
    ]) {
      _reg<DisplayViewPtrNative>(
          symbol,
          ffi.NativeCallable<DisplayViewPtrNative>.listener(
              (ffi.Pointer<ffi.Void> _) {}));
    }
  }

  // --- callback handlers ---

  void _onTimeEntryList(
      int open, ffi.Pointer<TogglTimeEntryView> first, int showLoadMore) {
    _timeEntries.add(_walkList(first));
    _showLoadMore.add(showLoadMore != 0);
  }

  void _onTimerState(ffi.Pointer<TogglTimeEntryView> te) {
    _timerState.add(te == ffi.nullptr ? null : _toModel(te.ref));
  }

  void _onLogin(int open, int userId) {
    _loginState.add(LoginEvent(loggedIn: open != 0, userId: userId));
  }

  void _onError(ffi.Pointer<Utf8> errmsg, int userError) {
    _errors.add(CoreError(
      message: errmsg == ffi.nullptr ? '' : errmsg.toDartString(),
      userError: userError != 0,
    ));
  }

  void _onOnlineState(int state) => _onlineState.add(state);

  // --- view-struct marshalling (FP-23) ---

  List<TimeEntry> _walkList(ffi.Pointer<TogglTimeEntryView> first) {
    final out = <TimeEntry>[];
    var node = first;
    while (node != ffi.nullptr) {
      out.add(_toModel(node.ref));
      node = node.ref.Next;
    }
    return out;
  }

  TimeEntry _toModel(TogglTimeEntryView v) => TimeEntry(
        id: v.ID,
        guid: _str(v.GUID),
        description: _str(v.Description),
        durationInSeconds: v.DurationInSeconds,
        duration: _str(v.Duration),
        projectLabel: _str(v.ProjectLabel),
        taskLabel: _str(v.TaskLabel),
        clientLabel: _str(v.ClientLabel),
        color: _str(v.Color),
        tags: _str(v.Tags),
        billable: v.Billable != 0,
        started: v.Started,
        ended: v.Ended,
        startTimeString: _str(v.StartTimeString),
        endTimeString: _str(v.EndTimeString),
        isHeader: v.IsHeader != 0,
        dateHeader: _str(v.DateHeader),
        dateDuration: _str(v.DateDuration),
        unsynced: v.Unsynced != 0,
        error: _str(v.Error),
        activityId: v.ActivityID,
      );

  // --- public actions (FP-21) ---

  void setBaseUrl(String url) =>
      _withUtf8(url, (p) => _bindings.setBaseUrl(_ctx, p));

  bool login(String email, String password) {
    return _withUtf8(email, (e) {
      return _withUtf8(password, (p) => _bindings.login(_ctx, e, p)) != 0;
    });
  }

  bool logout() => _bindings.logout(_ctx) != 0;

  bool continueEntry(String guid) =>
      _withUtf8(guid, (g) => _bindings.continueEntry(_ctx, g)) != 0;

  bool stop() => _bindings.stop(_ctx, 0) != 0;

  void dispose() {
    if (_ctx != ffi.nullptr) {
      _bindings.contextClear(_ctx);
      _ctx = ffi.nullptr;
    }
    for (final cb in _callbacks) {
      cb.close();
    }
    _callbacks.clear();
    _timeEntries.close();
    _showLoadMore.close();
    _timerState.close();
    _loginState.close();
    _errors.close();
    _onlineState.close();
  }

  // --- helpers ---

  static String _str(ffi.Pointer<Utf8> p) =>
      p == ffi.nullptr ? '' : p.toDartString();

  static T _withUtf8<T>(String s, T Function(ffi.Pointer<Utf8>) body) {
    final p = s.toNativeUtf8();
    try {
      return body(p);
    } finally {
      malloc.free(p);
    }
  }
}

/// Emitted on every `on_login` transition.
class LoginEvent {
  const LoginEvent({required this.loggedIn, required this.userId});
  final bool loggedIn;
  final int userId;
}

/// Emitted on every `on_error`.
class CoreError {
  const CoreError({required this.message, required this.userError});
  final String message;
  final bool userError;
}

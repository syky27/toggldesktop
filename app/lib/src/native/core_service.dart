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
/// Threading: callbacks are wired with [ffi.NativeCallable.listener] so the core
/// may invoke them from its own threads; the Dart handlers then run on this
/// isolate's event loop. See ADR-0001 for the struct-lifetime caveat and the
/// planned C bridge shim that deep-copies struct payloads.
class CoreService {
  CoreService._(this._bindings);

  final TogglBindings _bindings;
  ffi.Pointer<ffi.Void> _ctx = ffi.nullptr;

  // Retained NativeCallables — must be kept alive for the context's lifetime
  // and explicitly closed in [dispose].
  final List<ffi.NativeCallable<dynamic>> _callbacks = [];

  final _timeEntries = StreamController<List<TimeEntry>>.broadcast();
  final _showLoadMore = StreamController<bool>.broadcast();
  final _timerState = StreamController<TimeEntry?>.broadcast();
  final _loginState = StreamController<LoginEvent>.broadcast();
  final _errors = StreamController<CoreError>.broadcast();
  final _onlineState = StreamController<int>.broadcast();

  /// The current time-entry list (latest `on_time_entry_list`).
  Stream<List<TimeEntry>> get timeEntries => _timeEntries.stream;

  /// Whether a "load more" button should be shown.
  Stream<bool> get showLoadMore => _showLoadMore.stream;

  /// The running entry, or null when stopped.
  Stream<TimeEntry?> get timerState => _timerState.stream;

  /// Login transitions (logged-in / logged-out).
  Stream<LoginEvent> get loginState => _loginState.stream;

  /// Errors surfaced by the core.
  Stream<CoreError> get errors => _errors.stream;

  /// Online/offline/backend-down state (see `kOnlineState*` in the header).
  Stream<int> get onlineState => _onlineState.stream;

  /// Loads the native library, creates the core context, registers callbacks
  /// and starts the core. [dbPath] must be a writable file path (FP-25).
  static CoreService start({
    required String appName,
    required String appVersion,
    required String dbPath,
    String? logPath,
  }) {
    final bindings = TogglBindings(TogglLibrary.open());
    final service = CoreService._(bindings);
    service._init(appName, appVersion, dbPath, logPath);
    return service;
  }

  void _init(String appName, String appVersion, String dbPath, String? logPath) {
    final namePtr = appName.toNativeUtf8();
    final versionPtr = appVersion.toNativeUtf8();
    try {
      _ctx = _bindings.contextInit(namePtr, versionPtr);
    } finally {
      malloc.free(namePtr);
      malloc.free(versionPtr);
    }
    if (_ctx == ffi.nullptr) {
      throw StateError('toggl_context_init returned null');
    }

    if (logPath != null) {
      final p = logPath.toNativeUtf8();
      try {
        _bindings.setLogPath(p);
      } finally {
        malloc.free(p);
      }
    }

    _withUtf8(dbPath, (p) => _bindings.setDbPath(_ctx, p));

    _registerCallbacks();

    if (_bindings.uiStart(_ctx) == 0) {
      throw StateError('toggl_ui_start failed');
    }
  }

  void _registerCallbacks() {
    // --- struct-bearing callbacks (see ADR-0001 lifetime caveat) ---
    final teList = ffi.NativeCallable<DisplayTimeEntryListNative>.listener(
        _onTimeEntryList);
    _bindings.onTimeEntryList(_ctx, teList.nativeFunction);
    _callbacks.add(teList);

    final timer =
        ffi.NativeCallable<DisplayTimerStateNative>.listener(_onTimerState);
    _bindings.onTimerState(_ctx, timer.nativeFunction);
    _callbacks.add(timer);

    // --- scalar/string callbacks (fully safe with .listener) ---
    final login = ffi.NativeCallable<DisplayLoginNative>.listener(_onLogin);
    _bindings.onLogin(_ctx, login.nativeFunction);
    _callbacks.add(login);

    final error = ffi.NativeCallable<DisplayErrorNative>.listener(_onError);
    _bindings.onError(_ctx, error.nativeFunction);
    _callbacks.add(error);

    final online =
        ffi.NativeCallable<DisplayOnlineStateNative>.listener(_onOnlineState);
    _bindings.onOnlineState(_ctx, online.nativeFunction);
    _callbacks.add(online);
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

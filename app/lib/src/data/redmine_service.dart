import 'dart:async';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/time_entry.dart';
import '../util/project_color.dart';
import 'http_log.dart';
import 'offline_queue.dart';
import 'redmine_api_client.dart';

/// Persisted-credential keys, shared with the iOS background-reconcile isolate
/// (`platform/background_reconcile.dart`) so both read the same store.
const String kRedmineBaseUrlKey = 'redmine_base_url';
const String kRedmineApiKeyKey = 'redmine_api_key';

/// The "track multiple tasks at once" preference key. Owned here (the data
/// layer) and referenced by `MultiTaskSettingsNotifier` so the deep-link handler
/// can read the persisted value directly — the Riverpod notifier seeds `false`
/// synchronously and loads the real value async, so trusting it at cold-launch
/// deep-link time would race (a multi-task user could get the single-timer path).
const String kAllowConcurrentTrackingKey = 'allow_concurrent_tracking';

/// Pure-Dart Redmine backend — the native replacement for the FFI `CoreService`.
///
/// It deliberately keeps the **same public method/stream surface** the UI and
/// Riverpod providers already consume, so swapping it in touches no UI code.
/// Slice 0 implements login + account load + the time-entry list (and detects an
/// already-running cross-device entry); the running timer (start/stop/continue)
/// and editor writes land in later slices.
class RedmineService {
  RedmineService._();

  /// Async factory: restores a persisted session and, if present, auto-logs-in
  /// (the "instant relaunch" the Qt app gets from its saved session).
  /// [httpClient] and [queue] are injectable for tests; [clock] lets tests drive
  /// the reconcile grace/miss window deterministically (defaults to wall-clock).
  static Future<RedmineService> create({
    http.Client? httpClient,
    OfflineQueue? queue,
    HttpLogger? logger,
    DateTime Function()? clock,
  }) async {
    final s = RedmineService._()
      .._httpClient = httpClient
      .._queue = queue ?? OfflineQueue()
      .._logger = logger;
    if (clock != null) s._now = clock;
    await s._restore();
    return s;
  }

  http.Client? _httpClient;
  OfflineQueue _queue = OfflineQueue();
  HttpLogger? _logger;

  /// Wall-clock, injectable for tests (the reconcile drop-guard reads it).
  DateTime Function() _now = DateTime.now;

  // --- persisted config: base URL + settings in prefs; the API **key** in the
  //     OS keychain (flutter_secure_storage). Keychain calls are wrapped so a
  //     missing plugin (unit-test VM) or entitlement issue degrades gracefully
  //     (the key just isn't persisted) instead of crashing. ---
  static const _kBaseUrl = kRedmineBaseUrlKey;
  static const _kApiKey = kRedmineApiKeyKey;
  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  // Hybrid: prefer the OS keychain; fall back to prefs where the keychain isn't
  // available (an unsigned macOS dev build, or the unit-test VM). On iOS and a
  // signed macOS build the key lives only in the keychain.
  Future<String?> _readKey() async {
    try {
      final v = await _secure.read(key: _kApiKey);
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kApiKey);
  }

  Future<void> _writeKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await _secure.write(key: _kApiKey, value: value);
      await prefs.remove(_kApiKey); // keychain wrote → drop any plaintext copy
      return;
    } catch (_) {/* keychain unavailable */}
    await prefs.setString(_kApiKey, value);
  }

  Future<void> _deleteKey() async {
    try {
      await _secure.delete(key: _kApiKey);
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kApiKey);
  }

  String _baseUrl = '';
  String _apiKey = '';
  RedmineApiClient? _api;
  int _userId = 0;
  String _userName = '';
  String _userEmail = '';

  /// The Redmine host (scheme stripped) for the sidebar instance chip.
  String get host => _baseUrl.replaceFirst(RegExp(r'^https?://'), '');
  String get userName => _userName;
  String get userEmail => _userEmail;

  /// Browser URL for a Redmine issue (empty if no host/issue).
  String issueUrl(int issueId) {
    final base = _baseUrl.trim();
    if (base.isEmpty || issueId <= 0) return '';
    return '${base.replaceAll(RegExp(r'/+$'), '')}/issues/$issueId';
  }

  /// Masked API key for display, e.g. `••2f9a`.
  String get maskedKey => _apiKey.length >= 4
      ? '••${_apiKey.substring(_apiKey.length - 4)}'
      : '••••';

  // Resolved Redmine schema (defaults match the known-good backend; overwritten
  // by name at login — mirrors RedmineClient::ResolveSchema).
  int _cfStart = 12; // toggl_start
  int _cfStop = 14; // toggl_stop
  int _cfGuid = 13; // toggl_guid
  int _defaultActivityId = 6; // Development
  bool _activityUserSet = false; // a user-chosen default overrides resolution
  List<Activity> _activities = const [];

  // Whether the toggl_* custom fields are sent with writes. Off = "simple mode"
  // (plain hour logging; timestamps + calendar hidden). Auto-disabled (sticky)
  // when the instance rejects the fields; re-enabled manually in Settings.
  bool _sendCustomFields = true;
  // A user-entered field id (Settings) wins over name-resolution at login.
  bool _cfUserSet = false;
  // Per-session latch: once a written entry reads back WITH our custom-field
  // values, the fields are confirmed working and we stop the round-trip check.
  // Redmine silently *drops* (201, no 422) values for fields the user can't set,
  // so verifying the values stuck is the only reliable "fields work" signal.
  bool _cfVerified = false;

  static const _kCfSend = 'cf_send';
  static const _kCfStart = 'cf_id_start';
  static const _kCfStop = 'cf_id_stop';
  static const _kCfGuid = 'cf_id_guid';
  static const _kCfUserSet = 'cf_user_set';

  final _projects = <int, _Project>{};
  final _issues = <int, _Issue>{};

  // Completed entries by display-guid (for continue/edit lookups), the recent
  // list (for a sensible default start), and the running entries. The list is
  // usually empty or single; it holds more than one only when the user has
  // opted into concurrent tracking (multi_task_settings).
  final _entriesByGuid = <String, _Entry>{};
  List<_Entry> _recent = const [];

  /// Optimistic completed entries shown immediately after a calendar/idle
  /// create, before the POST + refresh round-trip lands. Keyed by toggl_guid;
  /// dropped in [_composeAndEmit] once the server reports the same guid.
  final _pendingCreates = <String, _Entry>{};
  final List<_RunningEntry> _running = [];

  /// A `redtick://start` deep link that arrived before login finished (cold
  /// launch from the browser). Replayed once login succeeds (see [_emitLogin]).
  ({int issueId, String? host})? _pendingLink;

  // Reconcile guard: a confirmed running entry must be absent from the server's
  // open set for this many consecutive reconciles — and be at least [_dropGrace]
  // old — before it's dropped. Absorbs transient read-misses (replication lag,
  // recent-window eviction, a mid-flight schema re-resolution) so the running
  // state never flaps to "stopped" while a timer is genuinely running. A real
  // remote stop is persistent, so it still clears within ~2 polls (≤60s).
  static const int _missesToDrop = 2;
  static const Duration _dropGrace = Duration(seconds: 45);

  Timer? _ticker;
  Timer? _poll; // periodic cross-device reconcile (running stop / remote start)
  bool _refreshing = false; // re-entrancy guard for refresh()
  DateTime? _lastSyncedAt;
  bool _disposed = false;

  /// Add to a stream only while alive — pending async (login/refresh/ticker) can
  /// outlive a [dispose] (e.g. between tests); never add to a closed controller.
  void _emit<T>(StreamController<T> c, T value) {
    if (!_disposed && !c.isClosed) c.add(value);
  }

  // --- streams (same names/types as CoreService) ---
  final _timeEntries = StreamController<List<TimeEntry>>.broadcast();
  final _showLoadMore = StreamController<bool>.broadcast();
  final _timerState = StreamController<TimeEntry?>.broadcast();
  // All running entries (≥0). `_timerState` carries just the primary so the
  // single-timer surfaces (idle / reminder) stay unchanged.
  final _runningEntries = StreamController<List<TimeEntry>>.broadcast();
  final _loginState = StreamController<LoginEvent>.broadcast();
  final _errors = StreamController<CoreError>.broadcast();
  final _onlineState = StreamController<int>.broadcast();
  final _reminders = StreamController<Notice>.broadcast();
  final _pomodoro = StreamController<Notice>.broadcast();
  final _idle = StreamController<IdleNotice>.broadcast();
  final _syncEvents = StreamController<DateTime>.broadcast();
  // Custom-field config (toggle + the three ids); drives Settings + the
  // simple-mode UI gating (calendar/timestamps). [_cfAutoDisabled] is a one-shot
  // signal carrying the alert message when a write rejection turns sending off.
  final _cfConfig = StreamController<CustomFieldConfig>.broadcast();
  final _cfAutoDisabled = StreamController<CustomFieldNotice>.broadcast();
  // One-shot outcomes of a `redtick://start` browser deep link (started /
  // confirm-concurrent / already-running / error). Wired in `app.dart` to a
  // toast, a confirm dialog, and `AppWindow.foreground()`.
  final _deepLinkNotices = StreamController<DeepLinkNotice>.broadcast();

  LoginEvent? _lastLogin;
  List<TimeEntry>? _lastTimeEntries;
  TimeEntry? _lastTimer;
  List<TimeEntry> _lastRunningList = const [];

  Stream<List<TimeEntry>> get timeEntries => _timeEntries.stream;
  Stream<bool> get showLoadMore => _showLoadMore.stream;
  Stream<TimeEntry?> get timerState => _timerState.stream;

  /// All currently-running entries (most-recently-started last). Drives the
  /// stacked top bar; empty when nothing is tracking.
  Stream<List<TimeEntry>> get runningEntries => _runningEntries.stream;
  Stream<LoginEvent> get loginState => _loginState.stream;
  Stream<CoreError> get errors => _errors.stream;
  Stream<int> get onlineState => _onlineState.stream;
  Stream<Notice> get reminders => _reminders.stream;
  Stream<Notice> get pomodoro => _pomodoro.stream;
  Stream<IdleNotice> get idle => _idle.stream;

  /// One-shot outcomes of handling a `redtick://start` browser deep link.
  Stream<DeepLinkNotice> get deepLinkNotices => _deepLinkNotices.stream;

  /// Emits the timestamp of each successful refresh (drives the desktop
  /// "Synced · Ns ago" indicator).
  Stream<DateTime> get syncEvents => _syncEvents.stream;

  /// When the account set was last successfully pulled (null until first sync).
  DateTime? get lastSyncedAt => _lastSyncedAt;

  /// Replayed for late subscribers (the UI subscribes after startup events).
  LoginEvent? get currentLogin => _lastLogin;
  List<TimeEntry>? get currentTimeEntries => _lastTimeEntries;
  TimeEntry? get currentTimer => _lastTimer;
  List<TimeEntry> get currentRunningEntries => _lastRunningList;

  /// The "primary" running entry = the most recently started one (or null). The
  /// single-timer surfaces (idle prompt, "not tracking" reminder, Live Activity
  /// when only one runs) act on this.
  _RunningEntry? get _primaryRunning {
    if (_running.isEmpty) return null;
    var p = _running.first;
    for (final e in _running) {
      if (e.start.isAfter(p.start)) p = e;
    }
    return p;
  }

  /// Whether a timer for [issueId] is already running (deep-link no-op guard).
  bool isIssueRunning(int issueId) =>
      _running.any((r) => r.issueId == issueId);

  List<Activity> get availableActivities => _activities;

  /// The activity name for [id] (empty if unknown) — for the timer/editor.
  String activityName(int id) {
    for (final a in _activities) {
      if (a.id == id) return a.name;
    }
    return '';
  }

  int get defaultActivityId => _defaultActivityId;

  // --- custom-field config (Settings + simple-mode gating) ---

  /// Config changes (toggle + ids): Settings, the calendar/timestamp gating.
  Stream<CustomFieldConfig> get customFieldConfig => _cfConfig.stream;

  /// One-shot notice when a write rejection auto-disables custom fields.
  Stream<CustomFieldNotice> get customFieldsAutoDisabled =>
      _cfAutoDisabled.stream;

  /// Current config (replayed for late subscribers, like the other state).
  CustomFieldConfig get currentCustomFieldConfig => CustomFieldConfig(
        sendCustomFields: _sendCustomFields,
        startId: _cfStart,
        stopId: _cfStop,
        guidId: _cfGuid,
      );

  bool get sendCustomFields => _sendCustomFields;
  int get cfStartId => _cfStart;
  int get cfStopId => _cfStop;
  int get cfGuidId => _cfGuid;

  void _emitCfConfig() => _emit(_cfConfig, currentCustomFieldConfig);

  /// Turn sending of the toggl_* custom fields on/off (persisted). Off hides the
  /// timestamps + Calendar and logs plain hours.
  Future<void> setSendCustomFields(bool v) async {
    if (_sendCustomFields == v) return;
    _sendCustomFields = v;
    if (v) _cfVerified = false; // re-enabled → re-verify on the next write
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCfSend, v);
    _emitCfConfig();
  }

  /// User-entered custom-field ids (Settings). Marks them user-set so login
  /// name-resolution won't overwrite them.
  Future<void> setCustomFieldIds({int? start, int? stop, int? guid}) async {
    if (start != null) _cfStart = start;
    if (stop != null) _cfStop = stop;
    if (guid != null) _cfGuid = guid;
    _cfUserSet = true;
    _cfVerified = false; // new ids → re-verify on the next write
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kCfStart, _cfStart);
    await prefs.setInt(_kCfStop, _cfStop);
    await prefs.setInt(_kCfGuid, _cfGuid);
    await prefs.setBool(_kCfUserSet, true);
    _emitCfConfig();
  }

  // The custom-field ids to write right now — the resolved id, or 0 (omit the
  // field) when sending is disabled. Used by the offline-queue enqueue paths.
  int get _outCfStart => _sendCustomFields ? _cfStart : 0;
  int get _outCfStop => _sendCustomFields ? _cfStop : 0;
  int get _outCfGuid => _sendCustomFields ? _cfGuid : 0;

  /// Run a write, retrying once without custom fields if Redmine rejects it
  /// while they were sent. A 422 typically means the instance doesn't have the
  /// toggl_* fields (their ids can't be discovered without admin) — so if the
  /// retry succeeds, the fields were the culprit: disable (sticky) + alert, and
  /// the entry is still saved. [op] receives whether to include custom fields.
  Future<T> _withCfRetry<T>(Future<T> Function(bool withCf) op) async {
    if (!_sendCustomFields) return op(false);
    try {
      return await op(true);
    } on RedmineException catch (e) {
      // Only a plain rejection (422 etc.) might be the fields; auth/network/
      // not-found are surfaced as-is.
      if (e.kind != RedmineErrorKind.generic) rethrow;
      final T result;
      try {
        result = await op(false);
      } catch (_) {
        throw e; // retry didn't help → not the fields; surface the original.
      }
      await _autoDisableCustomFields();
      return result;
    }
  }

  /// After a successful create that sent custom fields, read the entry back and
  /// confirm our values persisted. Redmine returns 201 and silently drops values
  /// for fields the user can't set (or that don't exist), so a successful POST
  /// is NOT proof the fields work — this round-trip is. If they didn't stick,
  /// switch to simple mode (disable + alert). Runs at most once per session.
  Future<void> _maybeVerifyCustomFields(int? id) async {
    if (!_sendCustomFields || _cfVerified || id == null || id <= 0) return;
    final api = _api;
    if (api == null) return;
    try {
      final te = await api.timeEntry(id);
      if (te == null) return; // gone already — can't verify; try next write
      final cfs = te['custom_fields'] as List?;
      final start = _customField(cfs, _cfStart) ?? '';
      final guid = _customField(cfs, _cfGuid) ?? '';
      if (start.isEmpty && guid.isEmpty) {
        await _autoDisableCustomFields();
      } else {
        _cfVerified = true;
      }
    } on RedmineException {
      // Couldn't read it back (transient) — don't penalize; verify next write.
    }
  }

  /// Probe whether the instance accepts our custom fields *right now*, so turning
  /// the setting on gives immediate feedback instead of waiting for the next real
  /// entry. Writes a tiny throwaway entry, reads it back, and deletes it —
  /// invisible to the UI (no optimistic insert / refresh). Best-effort: if it
  /// can't run (nothing to attach to, offline, or a create rejection) it leaves
  /// verification to the next real write. Only the round-trip check disables (so
  /// an unrelated create-validation error never falsely flips simple mode).
  /// Returns true only when the probe confirmed the fields work; false if it
  /// disabled them or couldn't run.
  Future<bool> verifyCustomFieldsNow() async {
    final api = _api;
    if (api == null || !_sendCustomFields) return false;
    if (_cfVerified) return true;
    var issueId = _recent.isNotEmpty ? _recent.first.tid : 0;
    var projectId = _recent.isNotEmpty ? _recent.first.pid : 0;
    if (issueId <= 0 && _issues.isNotEmpty) issueId = _issues.keys.first;
    if (issueId <= 0 && projectId <= 0 && _projects.isNotEmpty) {
      projectId = _projects.keys.first;
    }
    if (issueId <= 0 && projectId <= 0) return false; // nothing to attach to
    final now = DateTime.now();
    int? probeId;
    try {
      probeId = await api.createTimeEntry(
        issueId: issueId,
        projectId: projectId,
        hours: 0.01,
        spentOn: now,
        comments: 'Redtick custom-field self-check',
        activityId: _defaultActivityId,
        togglStart: _isoZ(now),
        togglStop: _isoZ(now),
        togglGuid: _uuid(),
        cfStart: _cfStart,
        cfStop: _cfStop,
        cfGuid: _cfGuid,
      );
      final te = await api.timeEntry(probeId);
      final cfs = te?['custom_fields'] as List?;
      final gotStart = _customField(cfs, _cfStart) ?? '';
      final gotGuid = _customField(cfs, _cfGuid) ?? '';
      if (gotStart.isEmpty && gotGuid.isEmpty) {
        await _autoDisableCustomFields();
        return false;
      }
      _cfVerified = true;
      return true;
    } on RedmineException {
      return false; // couldn't run the probe — leave it to the next real write
    } finally {
      if (probeId != null) {
        try {
          await api.deleteTimeEntry(probeId);
        } catch (_) {/* best effort cleanup */}
      }
    }
  }

  Future<void> _autoDisableCustomFields() async {
    if (!_sendCustomFields) return;
    await setSendCustomFields(false);
    _emit(
      _cfAutoDisabled,
      CustomFieldNotice(
        "Redtick couldn't save its custom fields on this Redmine instance — "
        "they're missing, or your account isn't allowed to set them. Sending "
        'them has been turned off, so your time is still logged as hours (the '
        'precise start/stop times and the Calendar are hidden). To use them, '
        'create the three time-entry custom fields described in the Redtick '
        "README (any names) and enter their IDs under Settings → 'Redmine "
        "custom fields', then turn this back on.",
      ),
    );
  }

  /// User-chosen default activity for new entries (persisted; design §3.8).
  Future<void> setDefaultActivity(int id) async {
    _defaultActivityId = id;
    _activityUserSet = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('default_activity_id', id);
  }

  /// Live issue search for the picker (design §3.7).
  Future<List<IssueResult>> searchIssues({
    String query = '',
    IssueScope scope = IssueScope.mine,
  }) async {
    final api = _api;
    if (api == null) return const [];
    try {
      final raw = await api.findIssues(
          query: query, scope: _scopeFilter(scope), maxItems: 50);
      return raw.map(_toIssueResult).toList();
    } on RedmineException catch (e) {
      _reportError(e);
      return const [];
    }
  }

  static String _scopeFilter(IssueScope s) => switch (s) {
        IssueScope.mine =>
          'assigned_to_id=me&status_id=open&sort=updated_on:desc',
        IssueScope.assigned =>
          'assigned_to_id=me&status_id=*&sort=updated_on:desc',
        IssueScope.all => 'status_id=*&sort=updated_on:desc',
      };

  static IssueResult _toIssueResult(Map<String, dynamic> i) => IssueResult(
        id: (i['id'] as num?)?.toInt() ?? 0,
        subject: (i['subject'] as String?) ?? '',
        projectId: ((i['project'] as Map?)?['id'] as num?)?.toInt() ?? 0,
        projectName: ((i['project'] as Map?)?['name'] as String?) ?? '',
        statusName: ((i['status'] as Map?)?['name'] as String?) ?? '',
        closed: ((i['status'] as Map?)?['is_closed'] as bool?) ?? false,
      );

  // --- login / session ---

  void setBaseUrl(String url) {
    _baseUrl = url.trim(); // the client normalizes (strips trailing slashes)
  }

  /// Starts an async login and returns immediately (true = request queued). The
  /// outcome arrives on [loginState] (success) or [errors] (failure) — the UI's
  /// auth gate flips on the login stream, never on this return value.
  bool login(String email, String password) {
    unawaited(_doLogin(password.trim()));
    return true;
  }

  Future<void> _doLogin(String apiKey) async {
    if (_baseUrl.trim().isEmpty) {
      _emit(_errors, const CoreError(
          message: 'Enter the Redmine host URL.', userError: true));
      return;
    }
    if (apiKey.isEmpty) {
      _emit(_errors, 
          const CoreError(message: 'Enter an API key.', userError: true));
      return;
    }
    _apiKey = apiKey;
    _cfVerified = false; // fresh session/instance → verify on the first write
    _api?.dispose();
    _api = RedmineApiClient(
        baseUrl: _baseUrl,
        apiKey: apiKey,
        client: _httpClient,
        logger: _logger);
    try {
      final user = await _api!.currentUser();
      _userId = (user['id'] as num).toInt();
      final first = (user['firstname'] as String?) ?? '';
      final last = (user['lastname'] as String?) ?? '';
      _userName = [first, last].where((s) => s.isNotEmpty).join(' ').trim();
      if (_userName.isEmpty) _userName = (user['login'] as String?) ?? '';
      _userEmail = (user['mail'] as String?) ?? '';
      _emit(_onlineState, 0); // online
      await _persist();
      _emitLogin(loggedIn: true, userId: _userId);
      await refresh();
      _startPoll(); // cross-device reconcile while logged in
    } on RedmineException catch (e) {
      _reportError(e);
    } catch (e) {
      _emit(_errors, CoreError(message: 'Login failed: $e', userError: true));
    }
  }

  /// Re-run login with the stored key (Settings → Reconnect).
  void reconnect() {
    if (_apiKey.isNotEmpty) unawaited(_doLogin(_apiKey));
  }

  bool logout() {
    _stopPoll();
    _api?.dispose();
    _api = null;
    _apiKey = '';
    _userId = 0;
    _projects.clear();
    _issues.clear();
    _running.clear();
    _lastTimeEntries = null;
    _lastTimer = null;
    _lastRunningList = const [];
    unawaited(_clearPersisted());
    _emitLogin(loggedIn: false, userId: 0);
    return true;
  }

  /// Re-pull the account set and rebuild the list + running-timer state.
  ///
  /// [silent] (used by the background poll) suppresses the user-facing error
  /// toast on failure — only `onlineState` is updated — so transient poll
  /// errors don't spam the UI.
  Future<void> refresh({bool silent = false}) async {
    final api = _api;
    if (api == null) return;
    if (_refreshing) return; // avoid overlapping pulls mutating the shared maps
    _refreshing = true;
    try {
      final projects = await api.projects();
      final issues = await api.myOpenIssues();
      final entries = await api.recentTimeEntries();
      await _resolveSchema(api, entries);

      _projects
        ..clear()
        ..addEntries(projects.map((p) {
          final id = (p['id'] as num).toInt();
          return MapEntry(
              id, _Project(id, (p['name'] as String?) ?? '', _colorFor(id)));
        }));
      _issues
        ..clear()
        ..addEntries(issues.map((i) {
          final id = (i['id'] as num).toInt();
          return MapEntry(
              id, _Issue(id, (i['subject'] as String?) ?? ''));
        }));

      _rebuild(entries);
      _emit(_onlineState, 0);
      _markSynced();
      await _flushQueue(api); // network is back → replay any queued writes
    } on RedmineException catch (e) {
      if (silent) {
        if (e.kind == RedmineErrorKind.network) _emit(_onlineState, 1);
      } else {
        _reportError(e);
      }
    } finally {
      _refreshing = false;
    }
  }

  void _markSynced() {
    _lastSyncedAt = DateTime.now();
    _emit(_syncEvents, _lastSyncedAt!);
  }

  /// Periodic cross-device reconcile. While a confirmed timer runs, cheaply
  /// check just that entry (`GET /time_entries/{id}`) and only do a full pull if
  /// it was stopped/deleted elsewhere; when idle, a full pull catches a timer
  /// started on another device. Always silent (no toast on transient errors).
  Future<void> _pollTick() async {
    if (_disposed || _refreshing) return;
    final api = _api;
    if (api == null) return;
    // Cheap single-entry GET only for the common single-confirmed-timer case;
    // with 0 (idle / in-flight start) or >1 running, a full pull is simpler and
    // also discovers timers started on another device.
    if (_running.length == 1 && _running.first.redmineId != null) {
      final r = _running.first;
      try {
        final te = await api.timeEntry(r.redmineId!);
        final mapped = te == null ? null : _mapEntry(te);
        if (mapped != null && mapped.running) {
          r.missStreak = 0; // confirmed open → reset
          _emit(_onlineState, 0); // reachable; keep ticking locally
        } else {
          // A single not-running read may be a transient lag/read-miss. Only do
          // the authoritative full reconcile (which drops it) once past the
          // grace window and after [_missesToDrop] consecutive misses.
          final age = r.confirmedAt == null
              ? Duration.zero
              : _now().difference(r.confirmedAt!);
          if (age >= _dropGrace && ++r.missStreak >= _missesToDrop) {
            await refresh(silent: true);
          } else {
            _emit(_onlineState, 0); // tolerate the miss; keep ticking
          }
        }
      } on RedmineException catch (e) {
        if (e.kind == RedmineErrorKind.network) _emit(_onlineState, 1);
      }
    } else {
      // _reconcileRunning guards in-flight local starts and merges remote ones.
      await refresh(silent: true);
    }
  }

  void _startPoll() {
    if (_disposed) return;
    _poll ??= Timer.periodic(const Duration(seconds: 30), (_) => _pollTick());
  }

  void _stopPoll() {
    _poll?.cancel();
    _poll = null;
  }

  /// Replay queued offline writes, then re-pull once if anything synced.
  Future<void> _flushQueue(RedmineApiClient api) async {
    if (_queue.length == 0) return;
    final n = await _queue.replay(api);
    if (n > 0) {
      try {
        _rebuild(await api.recentTimeEntries());
      } on RedmineException catch (_) {/* went offline again — keep what we have */}
    }
  }

  /// Resolve activity list + the toggl_* custom-field ids by NAME (mirrors
  /// RedmineClient::ResolveSchema), self-correcting if instance ids differ.
  Future<void> _resolveSchema(
      RedmineApiClient api, List<Map<String, dynamic>> entries) async {
    try {
      final acts = await api.activities();
      final list = <Activity>[];
      int byName = 0, byDefault = 0, firstActive = 0;
      for (final a in acts) {
        final id = (a['id'] as num?)?.toInt() ?? 0;
        if (id <= 0) continue;
        final active = a['active'] == null || a['active'] == true;
        final name = (a['name'] as String?) ?? '';
        if (active) list.add(Activity(id, name));
        if (byName == 0 && name.toLowerCase() == 'development') byName = id;
        if (byDefault == 0 && a['is_default'] == true) byDefault = id;
        if (firstActive == 0 && active) firstActive = id;
      }
      final chosen = byName != 0 ? byName : (byDefault != 0 ? byDefault : firstActive);
      if (chosen != 0 && !_activityUserSet) _defaultActivityId = chosen;
      if (list.isNotEmpty) _activities = list;
    } on RedmineException {
      // keep defaults
    }

    var fStart = false, fStop = false, fGuid = false;
    void match(List<dynamic>? fields) {
      for (final f in (fields ?? const [])) {
        if (f is! Map) continue;
        if (f['customized_type'] != null &&
            f['customized_type'] != 'time_entry') {
          continue;
        }
        final id = (f['id'] as num?)?.toInt() ?? 0;
        final name = f['name'] as String?;
        if (id <= 0 || name == null) continue;
        // A user-entered id (Settings) is authoritative — never overwrite it.
        if (name == 'toggl_start') {
          if (!_cfUserSet) _cfStart = id;
          fStart = true;
        } else if (name == 'toggl_stop') {
          if (!_cfUserSet) _cfStop = id;
          fStop = true;
        } else if (name == 'toggl_guid') {
          if (!_cfUserSet) _cfGuid = id;
          fGuid = true;
        }
      }
    }

    // Skip name-resolution entirely when the user pinned the ids in Settings
    // (also avoids the admin-only /custom_fields.json 403 for non-admins).
    if (!_cfUserSet) {
      for (final e in entries) {
        match(e['custom_fields'] as List?);
      }
      if (!(fStart && fStop && fGuid)) {
        final defs = await api.customFieldDefs();
        match(defs);
      }
      // Reflect any resolved ids in Settings. A genuine "fields are missing"
      // signal now comes from a write rejection (auto-disable + alert), not a
      // login-time guess — non-admins can't list field definitions at all.
      _emitCfConfig();
    }
  }

  // --- list building ---

  void _rebuild(List<Map<String, dynamic>> rawEntries) {
    final completed = <_Entry>[];
    final open = <_Entry>[]; // every open (toggl_stop empty) entry, any device
    for (final rt in rawEntries) {
      final e = _mapEntry(rt);
      if (e == null) continue;
      if (e.running) {
        open.add(e);
      } else {
        completed.add(e);
      }
    }

    completed.sort((a, b) => b.start.compareTo(a.start));
    _recent = completed;

    _reconcileRunning(open);

    _composeAndEmit();
  }

  /// Build the display list from the last server snapshot ([_recent]) plus any
  /// still-unconfirmed optimistic creates, then emit. Pending creates the
  /// server now reports (matched by toggl_guid) are dropped first, so the
  /// authoritative row replaces the placeholder with no duplicate.
  void _composeAndEmit() {
    if (_pendingCreates.isNotEmpty) {
      final serverGuids =
          _recent.map((e) => e.guid).where((g) => g.isNotEmpty).toSet();
      _pendingCreates.removeWhere((g, _) => serverGuids.contains(g));
    }
    final all = [..._recent, ..._pendingCreates.values]
      ..sort((a, b) => b.start.compareTo(a.start));
    _entriesByGuid
      ..clear()
      ..addEntries(all.map((e) => MapEntry(_displayGuid(e), e)));

    final list = _groupByDay(all);
    _lastTimeEntries = list;
    _emit(_timeEntries, list);
    _emit(_showLoadMore, false);
  }

  /// Reconcile the server's open entries (those whose `toggl_stop` is empty —
  /// the cross-device source of truth) with the local running list:
  ///  • adopt server-open entries we don't hold locally (started elsewhere);
  ///  • fill the server id onto matching local entries (keeping the richer
  ///    local instance with its sub-second start / in-memory edits);
  ///  • drop confirmed local entries the server no longer lists as open
  ///    (stopped on another device);
  ///  • keep in-flight local starts (no server id yet) the server hasn't
  ///    reflected.
  /// With ≤1 open entry this is exactly the old single-timer behaviour.
  void _reconcileRunning(List<_Entry> discovered) {
    // A server entry corresponds to a local one by guid (or by id when the open
    // row carries no toggl_guid — e.g. started in the Redmine web UI).
    _Entry? matchFor(_RunningEntry r) {
      for (final e in discovered) {
        if ((e.guid.isNotEmpty && e.guid == r.guid) ||
            (r.redmineId != null && r.redmineId == e.id)) {
          return e;
        }
      }
      return null;
    }

    // Adopt open entries with no local counterpart.
    for (final e in discovered) {
      final known = _running.any((r) =>
          (e.guid.isNotEmpty && e.guid == r.guid) ||
          (r.redmineId != null && r.redmineId == e.id));
      if (known) continue;
      _running.add(_RunningEntry(
        guid: e.guid.isNotEmpty ? e.guid : _uuid(),
        redmineId: e.id,
        issueId: e.tid,
        projectId: e.pid,
        activityId: e.activityId,
        description: e.description,
        start: e.start,
      )..confirmedAt = _now());
    }

    // Fill ids / drop entries stopped elsewhere; keep in-flight local starts and
    // tolerate transient server read-misses: a confirmed entry is only dropped
    // after [_missesToDrop] consecutive misses and never within [_dropGrace] of
    // confirmation, so the running state can't flap to "stopped" mid-track.
    final now = _now();
    final toRemove = <_RunningEntry>[];
    for (final r in _running) {
      final match = matchFor(r);
      if (match != null) {
        if (r.redmineId == null) {
          r.redmineId = match.id;
          r.confirmedAt = now;
        }
        r.missStreak = 0; // seen open → reset
      } else if (r.redmineId != null) {
        final age = r.confirmedAt == null
            ? Duration.zero
            : now.difference(r.confirmedAt!);
        if (age >= _dropGrace && ++r.missStreak >= _missesToDrop) {
          toRemove.add(r);
        }
      }
      // r.redmineId == null && no match → in-flight local start; keep it.
    }
    _running.removeWhere(toRemove.contains);

    _emitRunning();
  }

  _Entry? _mapEntry(Map<String, dynamic> rt) {
    final id = (rt['id'] as num?)?.toInt() ?? 0;
    final pid = ((rt['project'] as Map?)?['id'] as num?)?.toInt() ?? 0;
    final tid = ((rt['issue'] as Map?)?['id'] as num?)?.toInt() ?? 0;
    final activityId =
        ((rt['activity'] as Map?)?['id'] as num?)?.toInt() ?? 0;
    final comments = (rt['comments'] as String?) ?? '';
    final cfs = rt['custom_fields'] as List?;
    final startStr = _customField(cfs, _cfStart);
    final stopStr = _customField(cfs, _cfStop);
    final guid = _customField(cfs, _cfGuid) ?? '';

    DateTime? start = _parse8601(startStr);
    DateTime? stop = _parse8601(stopStr);
    final running = start != null && (stopStr == null || stopStr.isEmpty);

    if (!running) {
      if (start == null || stop == null || !stop.isAfter(start)) {
        // Logged in the Redmine web UI: synthesize from spent_on (09:00) + hours.
        start = _synthStart(rt['spent_on'] as String?);
        final hours = (rt['hours'] as num?)?.toDouble() ?? 0;
        var durSec = (hours * 3600).round();
        if (durSec < 1) durSec = 1;
        stop = start.add(Duration(seconds: durSec));
      }
    }

    return _Entry(
      id: id,
      guid: guid,
      pid: pid,
      tid: tid,
      activityId: activityId == 0 ? _defaultActivityId : activityId,
      description: comments,
      start: start,
      stop: running ? null : stop,
      running: running,
    );
  }

  /// A completed entry → display model.
  TimeEntry _toModel(_Entry e) {
    final project = _projects[e.pid];
    final startEpoch = e.start.millisecondsSinceEpoch ~/ 1000;
    final durSec = e.stop!.difference(e.start).inSeconds;
    return TimeEntry(
      id: e.id,
      guid: _displayGuid(e),
      description: e.description,
      durationInSeconds: durSec,
      duration: _fmtDuration(durSec),
      projectLabel: _projectLabel(e.pid),
      taskLabel: _taskLabel(e.tid),
      clientLabel: '',
      color: project?.color ?? projectColorHex(null),
      tags: '',
      billable: false,
      started: startEpoch,
      ended: e.stop!.millisecondsSinceEpoch ~/ 1000,
      startTimeString: _fmtClock(e.start),
      endTimeString: _fmtClock(e.stop!),
      isHeader: false,
      dateHeader: '',
      dateDuration: '',
      unsynced: false,
      error: '',
      activityId: e.activityId,
    );
  }

  /// The running entry → display model (negative duration ⇒ `isRunning`).
  TimeEntry _runningModel(_RunningEntry r) {
    final project = _projects[r.projectId];
    final startEpoch = r.start.millisecondsSinceEpoch ~/ 1000;
    var durSec = DateTime.now().difference(r.start).inSeconds;
    if (durSec < 0) durSec = 0;
    return TimeEntry(
      id: r.redmineId ?? 0,
      guid: r.guid,
      description: r.description,
      durationInSeconds: -startEpoch,
      duration: _fmtDuration(durSec),
      projectLabel: _projectLabel(r.projectId),
      taskLabel: _taskLabel(r.issueId),
      clientLabel: '',
      color: project?.color ?? projectColorHex(null),
      tags: '',
      billable: false,
      started: startEpoch,
      ended: 0,
      startTimeString: _fmtClock(r.start),
      endTimeString: '',
      isHeader: false,
      dateHeader: '',
      dateDuration: '',
      unsynced: r.redmineId == null,
      error: '',
      activityId: r.activityId,
    );
  }

  String _projectLabel(int pid) =>
      _projects[pid]?.name ?? (pid == 0 ? '' : 'Project $pid');

  String _taskLabel(int tid) {
    if (tid == 0) return '';
    final issue = _issues[tid];
    return issue != null ? '#$tid: ${issue.subject}' : '#$tid';
  }

  // Key completed entries by their unique Redmine id (not the toggl_guid, which
  // can collide if a perceived-failed start actually committed) so continue /
  // edit / delete never resolve to the wrong row.
  static String _displayGuid(_Entry e) =>
      e.id > 0 ? 'rm-${e.id}' : (e.guid.isNotEmpty ? e.guid : 'rm-0');

  List<TimeEntry> _groupByDay(List<_Entry> entries) {
    final out = <TimeEntry>[];
    var lastKey = '';
    var dayEntries = <_Entry>[];

    void flushHeader(int insertAt, List<_Entry> group) {
      if (group.isEmpty) return;
      final total =
          group.fold<int>(0, (s, e) => s + e.stop!.difference(e.start).inSeconds);
      out.insert(
          insertAt,
          _header(dateLabel: _dayLabel(group.first.start), total: total));
    }

    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final key = _dayKey(e.start);
      if (key != lastKey) {
        flushHeader(out.length - dayEntries.length, dayEntries);
        dayEntries = [];
        lastKey = key;
      }
      out.add(_toModel(e));
      dayEntries.add(e);
    }
    flushHeader(out.length - dayEntries.length, dayEntries);
    return out;
  }

  TimeEntry _header({required String dateLabel, required int total}) => TimeEntry(
        id: 0,
        guid: '',
        description: '',
        durationInSeconds: 0,
        duration: '',
        projectLabel: '',
        taskLabel: '',
        clientLabel: '',
        color: '',
        tags: '',
        billable: false,
        started: 0,
        ended: 0,
        startTimeString: '',
        endTimeString: '',
        isHeader: true,
        dateHeader: dateLabel,
        dateDuration: _fmtDuration(total),
        unsynced: false,
        error: '',
        activityId: 0,
      );

  // --- running timer (Slice 1) ---

  /// Start a new running entry. With no issue picker yet (Slice 3) this defaults
  /// to the most-recent entry's issue/activity; use [continueEntry] to start
  /// against a specific past entry.
  String startEntry({String description = '', String tags = ''}) {
    final base = _recent.isNotEmpty ? _recent.first : null;
    if (base == null) {
      _emit(_errors, const CoreError(
          message: 'Pick an issue to start — use Continue (▶) on an entry.',
          userError: true));
      return '';
    }
    unawaited(_startRunning(
      issueId: base.tid,
      projectId: base.pid,
      activityId: base.activityId,
      description: description.isNotEmpty ? description : base.description,
    ));
    return '';
  }

  /// Continue a past entry: start a new running entry against its issue.
  /// [stopOthers] (false when concurrent tracking is enabled) keeps any other
  /// running timers going instead of stopping them first.
  bool continueEntry(String guid, {bool stopOthers = true}) {
    final e = _entriesByGuid[guid];
    if (e == null) return false;
    unawaited(_startRunning(
      issueId: e.tid,
      projectId: e.pid,
      activityId: e.activityId,
      description: e.description,
      stopOthers: stopOthers,
    ));
    return true;
  }

  /// Start a timer against an explicitly-picked issue (from the issue picker).
  /// [stopOthers] (false when concurrent tracking is enabled) keeps any other
  /// running timers going instead of stopping them first.
  void startEntryForIssue({
    required int issueId,
    required int projectId,
    String subject = '',
    String projectName = '',
    String description = '',
    int? activityId,
    bool stopOthers = true,
  }) {
    if (issueId != 0 && subject.isNotEmpty) {
      _issues[issueId] = _Issue(issueId, subject);
    }
    if (projectId != 0 && projectName.isNotEmpty &&
        !_projects.containsKey(projectId)) {
      _projects[projectId] =
          _Project(projectId, projectName, _colorFor(projectId));
    }
    unawaited(_startRunning(
      issueId: issueId,
      projectId: projectId,
      activityId: activityId ?? _defaultActivityId,
      description: description,
      stopOthers: stopOthers,
    ));
  }

  /// Handle a `redtick://start?issue=N&host=H` browser deep link (design: the
  /// Chrome/Firefox extension launches it from a Redmine issue page). Runs the
  /// state machine and surfaces the result on [deepLinkNotices]; the UI reacts
  /// (foreground + toast, or a confirm dialog for concurrent tracking).
  ///
  ///  1. [host] guard — refuse an issue from a Redmine other than the one we're
  ///     logged into (the "one host" invariant).
  ///  2. Not logged in yet (cold launch) — queue the link and replay it once
  ///     login succeeds; surface a "log in first" notice meanwhile.
  ///  3. Resolve the issue by number (needs its project + subject to start).
  ///  4. Already tracking that issue — no-op notice.
  ///  5. Multi-task OFF → stop the current timer and start this one; ON → emit
  ///     `confirmConcurrent` and let the UI ask before stacking it. The setting
  ///     is read straight from prefs (not passed in) so a cold-launch link can't
  ///     race the async load of `multiTaskSettingsProvider`.
  Future<void> handleStartDeepLink(int issueId, {String? host}) async {
    if (host != null && host.isNotEmpty && !_hostMatches(host)) {
      _emit(_deepLinkNotices,
          DeepLinkNotice.error('That issue is on a different Redmine ($host).'));
      return;
    }
    // `_userId == 0` covers both "no session" and "login still in flight": queue
    // and let [_emitLogin] replay it when the session is ready.
    if (_userId == 0) {
      _pendingLink = (issueId: issueId, host: host);
      _emit(_deepLinkNotices, DeepLinkNotice.error(
          'Log in to Redtick first, then click "Start in Redtick" again.'));
      return;
    }
    final results =
        await searchIssues(query: '$issueId', scope: IssueScope.all);
    IssueResult? issue;
    for (final r in results) {
      if (r.id == issueId) {
        issue = r;
        break;
      }
    }
    if (issue == null) {
      _emit(_deepLinkNotices, DeepLinkNotice.error(
          "Couldn't find issue #$issueId on this Redmine."));
      return;
    }
    if (isIssueRunning(issueId)) {
      _emit(_deepLinkNotices, DeepLinkNotice.alreadyRunning(
          issueId: issueId, subject: issue.subject));
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    final allowConcurrent = prefs.getBool(kAllowConcurrentTrackingKey) ?? false;
    if (!allowConcurrent) {
      startEntryForIssue(
        issueId: issue.id,
        projectId: issue.projectId,
        subject: issue.subject,
        projectName: issue.projectName,
        description: issue.subject,
        stopOthers: true,
      );
      _emit(_deepLinkNotices, DeepLinkNotice.started(
          issueId: issue.id, subject: issue.subject));
    } else {
      _emit(_deepLinkNotices, DeepLinkNotice.confirmConcurrent(
        issueId: issue.id,
        subject: issue.subject,
        projectId: issue.projectId,
        projectName: issue.projectName,
      ));
    }
  }

  /// Whether [linkHost] (the page's `location.host`) is the Redmine we're logged
  /// into. Compares hostnames only — scheme, port and any path are stripped.
  bool _hostMatches(String linkHost) {
    String norm(String s) => s
        .replaceFirst(RegExp(r'^https?://'), '')
        .split('/')
        .first
        .split(':')
        .first
        .toLowerCase()
        .trim();
    final mine = norm(host);
    return mine.isNotEmpty && mine == norm(linkHost);
  }

  /// Stop the primary (most-recently-started) running entry.
  bool stop() {
    unawaited(_stopRunning());
    return true;
  }

  /// Stop a specific running entry (the per-card Stop button when several run).
  bool stopEntry(String guid) {
    unawaited(_stopRunning(guid: guid));
    return true;
  }

  /// Adjust a running entry's start time (e.g. you began tracking a few minutes
  /// late and want the elapsed to reflect when you actually started). Shifts the
  /// local start so the elapsed reflects [newStart], updates the UI at once, and
  /// pushes `toggl_start` to Redmine when the open row already exists on the
  /// server. In simple mode (or while the start POST is still deferred) the new
  /// start is carried into the create/finalize write at stop instead.
  Future<bool> adjustRunningStart(String guid, DateTime newStart) async {
    _RunningEntry? r;
    for (final e in _running) {
      if (e.guid == guid) {
        r = e;
        break;
      }
    }
    if (r == null) return false;
    // Can't start in the future — clamp so the elapsed never goes negative.
    final now = DateTime.now();
    if (newStart.isAfter(now)) newStart = now;
    r.start = newStart;
    _emitRunning(); // top-bar duration + start reflect it instantly

    final api = _api;
    // Simple mode: no server row while running — the adjusted start flows into
    // the create-on-stop write via r.start. Nothing to PUT now.
    if (api == null || !_sendCustomFields) return true;
    // If the start POST is still in flight, wait for its id before updating.
    int? id = r.redmineId;
    if (id == null && r.createFuture != null) id = await r.createFuture;
    // Start POST failed/deferred → no server row yet; stop will create it.
    if (id == null) return true;
    final entryId = id;
    try {
      // hours left null ⇒ stays 0 (still an open/running entry); only move start.
      await _withCfRetry((withCf) => api.updateTimeEntry(
            id: entryId,
            spentOn: newStart,
            togglStart: _isoZ(newStart),
            cfStart: withCf ? _cfStart : 0,
          ));
      return true;
    } on RedmineException catch (e) {
      if (e.kind == RedmineErrorKind.network) {
        await _queue.enqueue({
          'kind': 'update',
          'id': entryId,
          'spentOn': newStart.millisecondsSinceEpoch,
          'togglStart': _isoZ(newStart),
          'cfStart': _outCfStart,
        });
        _emit(_onlineState, 1);
        return true; // optimistically saved (queued)
      }
      _reportError(e);
      return false;
    }
  }

  /// Stop every running entry except the most recently started one. Used when
  /// the user switches concurrent tracking off while several timers run.
  void collapseRunningToMostRecent() {
    final keep = _primaryRunning;
    if (keep == null) return;
    final others =
        _running.where((e) => e.guid != keep.guid).map((e) => e.guid).toList();
    if (others.isEmpty) return;
    unawaited(() async {
      for (final g in others) {
        await _stopRunning(guid: g);
      }
    }());
  }

  /// Stop the running entry at [stopTime] (idle prompt → discard the idle tail).
  void stopRunningAt(DateTime stopTime) => unawaited(_stopRunning(at: stopTime));

  /// Idle prompt → "Add idle as a new entry": trim the current running entry to
  /// [idleStart], then log the idle period (idleStart → now) as a NEW completed
  /// entry against the picked issue (e.g. attribute an interruption to a meeting).
  void logIdleAsNewEntry(
    DateTime idleStart, {
    required int issueId,
    required int projectId,
    String subject = '',
    String projectName = '',
    int? activityId,
  }) {
    if (issueId != 0 && subject.isNotEmpty) {
      _issues[issueId] = _Issue(issueId, subject);
    }
    if (projectId != 0 &&
        projectName.isNotEmpty &&
        !_projects.containsKey(projectId)) {
      _projects[projectId] =
          _Project(projectId, projectName, _colorFor(projectId));
    }
    unawaited(() async {
      await _stopRunning(at: idleStart); // trim idle off the current entry
      await _createCompletedEntry(
        issueId: issueId,
        projectId: projectId,
        description: subject,
        start: idleStart,
        end: DateTime.now(),
        activityId: activityId ?? _defaultActivityId,
      );
    }());
  }

  /// Calendar tap-to-create: create a COMPLETED entry placed at an explicit
  /// [start]/[end] against the picked issue. Mirrors [logIdleAsNewEntry]'s
  /// label registration, then posts via [_createCompletedEntry].
  Future<void> createEntryAt({
    required int issueId,
    required int projectId,
    required DateTime start,
    required DateTime end,
    String description = '',
    String subject = '',
    String projectName = '',
    int? activityId,
  }) async {
    if (issueId != 0 && subject.isNotEmpty) {
      _issues[issueId] = _Issue(issueId, subject);
    }
    if (projectId != 0 &&
        projectName.isNotEmpty &&
        !_projects.containsKey(projectId)) {
      _projects[projectId] =
          _Project(projectId, projectName, _colorFor(projectId));
    }
    await _createCompletedEntry(
      issueId: issueId,
      projectId: projectId,
      description: description,
      start: start,
      end: end,
      activityId: activityId ?? _defaultActivityId,
    );
  }

  /// POST a finished entry directly (used by the idle "add as new" flow);
  /// queues offline like the other writes.
  Future<void> _createCompletedEntry({
    required int issueId,
    required int projectId,
    required String description,
    required DateTime start,
    required DateTime end,
    required int activityId,
  }) async {
    final api = _api;
    if (api == null) return;
    var hours = end.difference(start).inSeconds / 3600.0;
    if (hours < 0) hours = 0;
    final guid = _uuid();

    // Optimistic: surface the entry immediately so the calendar/list update the
    // instant the issue is picked, not after the POST + refresh round-trip.
    _pendingCreates[guid] = _Entry(
      id: 0,
      guid: guid,
      pid: projectId,
      tid: issueId,
      activityId: activityId,
      description: description,
      start: start,
      stop: end,
      running: false,
    );
    _composeAndEmit();

    try {
      final newId = await _withCfRetry((withCf) => api.createTimeEntry(
            issueId: issueId,
            projectId: projectId,
            hours: hours,
            spentOn: start,
            comments: description,
            activityId: activityId,
            togglStart: _isoZ(start),
            togglStop: _isoZ(end),
            togglGuid: guid,
            cfStart: withCf ? _cfStart : 0,
            cfStop: withCf ? _cfStop : 0,
            cfGuid: withCf ? _cfGuid : 0,
          ));
      await _maybeVerifyCustomFields(newId);
      await refresh();
      // The authoritative row (if the server reflects it) is now in _recent;
      // clear the placeholder unconditionally so a guid that failed to
      // round-trip can never linger as a phantom that narrows real entries.
      if (_pendingCreates.remove(guid) != null) _composeAndEmit();
    } on RedmineException catch (e) {
      if (e.kind == RedmineErrorKind.network) {
        await _queue.enqueue({
          'kind': 'create',
          'issueId': issueId,
          'projectId': projectId,
          'hours': hours,
          'spentOn': start.millisecondsSinceEpoch,
          'comments': description,
          'activityId': activityId,
          'togglStart': _isoZ(start),
          'togglStop': _isoZ(end),
          'togglGuid': guid,
          'cfStart': _outCfStart,
          'cfStop': _outCfStop,
          'cfGuid': _outCfGuid,
        });
        _emit(_onlineState, 1);
        // Keep the optimistic entry visible; it syncs when the queue flushes.
      } else {
        _pendingCreates.remove(guid);
        _composeAndEmit(); // hard failure → roll back the placeholder
        _reportError(e);
      }
    }
  }

  /// Trim the idle tail (stop at [idleStart]) and immediately resume the same
  /// issue with a fresh entry (idle prompt → "Discard & continue").
  void discardIdleAndContinue(DateTime idleStart) {
    final r = _primaryRunning;
    if (r == null) return;
    final guid = r.guid;
    final issueId = r.issueId;
    final projectId = r.projectId;
    final activityId = r.activityId;
    final description = r.description;
    unawaited(() async {
      await _stopRunning(guid: guid, at: idleStart);
      // Only the trimmed entry is restarted — never disturb other concurrent
      // timers (idle handling is scoped to the primary entry).
      await _startRunning(
        issueId: issueId,
        projectId: projectId,
        activityId: activityId,
        description: description,
        stopOthers: false,
      );
    }());
  }

  Future<void> _startRunning({
    required int issueId,
    required int projectId,
    required int activityId,
    required String description,
    bool stopOthers = true,
  }) async {
    final api = _api;
    if (api == null) return;
    if (issueId <= 0 && projectId <= 0) {
      _emit(_errors, const CoreError(
          message: 'Pick an issue to start — use Continue (▶) on an entry.',
          userError: true));
      return;
    }
    // Single-timer mode (the default): stop whatever is running first. With
    // concurrent tracking on, the new timer is appended alongside the others.
    // Only await when something is actually running, so an idle start still
    // adds the entry synchronously (a stop() right after must see it).
    if (stopOthers && _running.isNotEmpty) await _stopAllRunning();

    final now = DateTime.now();
    final guid = _uuid();
    final act = activityId == 0 ? _defaultActivityId : activityId;
    // Optimistic: show it running immediately, then POST.
    final entry = _RunningEntry(
      guid: guid,
      redmineId: null,
      issueId: issueId,
      projectId: projectId,
      activityId: act,
      description: description,
      start: now,
    );
    _running.add(entry);
    _emitRunning();

    // Simple mode (custom fields off): the server can't represent a "running"
    // entry (no open toggl_stop), so defer — track locally now, create one
    // completed entry on stop. Leave redmineId/createFuture null.
    if (!_sendCustomFields) return;

    // Track the in-flight create so a fast stop can await its id instead of
    // posting a duplicate (this future never throws — errors are reported).
    entry.createFuture = api
        .createTimeEntry(
          issueId: issueId,
          projectId: projectId,
          hours: 0,
          spentOn: now,
          comments: description,
          activityId: act,
          togglStart: _isoZ(now),
          togglStop: '',
          togglGuid: guid,
          cfStart: _cfStart,
          cfStop: _cfStop,
          cfGuid: _cfGuid,
        )
        .then<int?>((id) {
      for (final e in _running) {
        if (e.guid == guid) {
          e.redmineId = id;
          e.confirmedAt = _now(); // start POST confirmed → start the grace clock
          break;
        }
      }
      _emit(_onlineState, 0);
      // Confirm the toggl_* values actually persisted (Redmine may have silently
      // dropped them) — disables + alerts if not.
      unawaited(_maybeVerifyCustomFields(id));
      return id;
    }).catchError((Object e) {
      // A plain rejection (e.g. the instance lacks the toggl_* fields) keeps the
      // timer local/deferred — stop will create it (and detect/disable+alert via
      // _withCfRetry). Only auth/network/not-found surface here.
      if (e is RedmineException && e.kind != RedmineErrorKind.generic) {
        _reportError(e);
      }
      return null;
    });
    await entry.createFuture;
  }

  /// Stop every running entry (snapshot first — `_stopRunning` mutates the list).
  Future<void> _stopAllRunning() async {
    final guids = _running.map((e) => e.guid).toList();
    for (final g in guids) {
      await _stopRunning(guid: g);
    }
  }

  /// Stop a running entry: the one with [guid], or the primary when [guid] is
  /// null (the toolbar Stop / idle trim). [at] lets the idle prompt trim the
  /// idle tail.
  Future<void> _stopRunning({String? guid, DateTime? at}) async {
    final api = _api;
    if (api == null) return;
    _RunningEntry? r;
    if (guid == null) {
      r = _primaryRunning;
    } else {
      for (final e in _running) {
        if (e.guid == guid) {
          r = e;
          break;
        }
      }
    }
    if (r == null) return;
    final re = r; // non-null capture for the create closure below
    _running.remove(r);
    _emitRunning();

    // [at] lets the idle prompt trim the idle tail; clamp to not precede start.
    var stop = at ?? DateTime.now();
    if (stop.isBefore(r.start)) stop = r.start;
    var hours = stop.difference(r.start).inSeconds / 3600.0;
    if (hours < 0) hours = 0; // clock skew / cross-device start ahead of now
    // If the start POST is still in flight, wait for its id and PUT the stop
    // onto that row — never post a second (duplicate) entry.
    int? id = r.redmineId;
    if (id == null && r.createFuture != null) id = await r.createFuture;
    final entryId = id;
    try {
      if (entryId != null) {
        await _withCfRetry((withCf) => api.updateTimeEntry(
              id: entryId,
              hours: hours,
              // Re-send toggl_start so a start adjusted while offline / in simple
              // mode (never PUT mid-run) still lands on the finalized row —
              // keeps the server start == local start.
              togglStart: _isoZ(re.start),
              togglStop: _isoZ(stop),
              cfStart: withCf ? _cfStart : 0,
              cfStop: withCf ? _cfStop : 0,
            ));
      } else {
        // No server row yet (deferred simple-mode timer, or a failed start POST)
        // — create the finished entry now.
        final newId = await _withCfRetry((withCf) => api.createTimeEntry(
              issueId: re.issueId,
              projectId: re.projectId,
              hours: hours,
              spentOn: re.start,
              comments: re.description,
              activityId: re.activityId,
              togglStart: _isoZ(re.start),
              togglStop: _isoZ(stop),
              togglGuid: re.guid,
              cfStart: withCf ? _cfStart : 0,
              cfStop: withCf ? _cfStop : 0,
              cfGuid: withCf ? _cfGuid : 0,
            ));
        await _maybeVerifyCustomFields(newId);
      }
      await refresh();
    } on RedmineException catch (e) {
      if (e.kind == RedmineErrorKind.network) {
        await _queue.enqueue(entryId != null
            ? {
                'kind': 'update',
                'id': entryId,
                'hours': hours,
                'togglStart': _isoZ(r.start),
                'togglStop': _isoZ(stop),
                'cfStart': _outCfStart,
                'cfStop': _outCfStop,
              }
            : {
                'kind': 'create',
                'issueId': r.issueId,
                'projectId': r.projectId,
                'hours': hours,
                'spentOn': r.start.millisecondsSinceEpoch,
                'comments': r.description,
                'activityId': r.activityId,
                'togglStart': _isoZ(r.start),
                'togglStop': _isoZ(stop),
                'togglGuid': r.guid,
                'cfStart': _outCfStart,
                'cfStop': _outCfStop,
                'cfGuid': _outCfGuid,
              });
        _emit(_onlineState, 1);
        _emit(_errors, const CoreError(
            message: 'Offline — the stop will sync when you reconnect.',
            userError: false));
      } else {
        _reportError(e);
      }
    }
  }

  void _emitRunning() {
    if (_disposed) return;
    // Oldest first so the most-recently-started (the "primary") is last.
    final sorted = [..._running]..sort((a, b) => a.start.compareTo(b.start));
    final list = sorted.map(_runningModel).toList(growable: false);
    _lastRunningList = list;
    _emit(_runningEntries, list);
    // The single-timer view = the primary (most recent), or null when idle.
    _lastTimer = list.isEmpty ? null : list.last;
    _emit(_timerState, _lastTimer);
    if (_running.isEmpty) {
      _stopTicker();
    } else {
      _startTicker();
    }
  }

  void _startTicker() {
    if (_disposed) return;
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      if (_running.isEmpty) {
        _stopTicker();
        return;
      }
      _emitRunning();
    });
  }

  void _stopTicker() {
    _ticker?.cancel();
    _ticker = null;
  }

  // --- editor writes (Slice 2) ---

  bool deleteEntry(String guid) {
    final e = _entriesByGuid[guid];
    if (e == null) return false;
    unawaited(_deleteEntry(e.id));
    return true;
  }

  Future<void> _deleteEntry(int id) async {
    final api = _api;
    if (api == null) return;
    try {
      await api.deleteTimeEntry(id);
      await refresh();
    } on RedmineException catch (e) {
      if (e.kind == RedmineErrorKind.network) {
        await _queue.enqueue({'kind': 'delete', 'id': id});
        _emit(_onlineState, 1);
      } else {
        _reportError(e);
      }
    }
  }

  /// Save edits to a completed entry (design editor §3.6) in a single PUT.
  Future<bool> updateEntry({
    required String guid,
    String? description,
    DateTime? start,
    DateTime? end,
    int? activityId,
    int? issueId,
    String? issueSubject,
  }) async {
    final api = _api;
    final e = _entriesByGuid[guid];
    if (api == null || e == null) return false;
    final newStart = start ?? e.start;
    final newEnd = end ?? e.stop ?? newStart.add(const Duration(minutes: 1));
    var hours = newEnd.difference(newStart).inSeconds / 3600.0;
    if (hours < 0) hours = 0;
    if (issueId != null && issueId != 0 && (issueSubject ?? '').isNotEmpty) {
      _issues[issueId] = _Issue(issueId, issueSubject!);
    }
    try {
      await _withCfRetry((withCf) => api.updateTimeEntry(
            id: e.id,
            hours: hours,
            comments: description,
            activityId: activityId,
            issueId: issueId,
            spentOn: newStart,
            togglStart: _isoZ(newStart),
            togglStop: _isoZ(newEnd),
            cfStart: withCf ? _cfStart : 0,
            cfStop: withCf ? _cfStop : 0,
          ));
      await _maybeVerifyCustomFields(e.id);
      await refresh();
      return true;
    } on RedmineException catch (ex) {
      if (ex.kind == RedmineErrorKind.network) {
        await _queue.enqueue({
          'kind': 'update',
          'id': e.id,
          'hours': hours,
          'comments': description,
          'activityId': activityId,
          'issueId': issueId,
          'spentOn': newStart.millisecondsSinceEpoch,
          'togglStart': _isoZ(newStart),
          'togglStop': _isoZ(newEnd),
          'cfStart': _outCfStart,
          'cfStop': _outCfStop,
        });
        _emit(_onlineState, 1);
        _emit(_errors, const CoreError(
            message: 'Offline — your edit will sync when you reconnect.',
            userError: false));
        return true; // optimistically saved (queued)
      }
      _reportError(ex);
      return false;
    }
  }

  /// Simple-mode editor save: update the fields a no-timestamp entry can have —
  /// duration (the standard `hours` field, which needs no custom fields),
  /// comments, activity, issue, date — sending no toggl_* custom fields.
  Future<bool> updateEntryFields({
    required String guid,
    String? description,
    int? activityId,
    int? issueId,
    String? issueSubject,
    DateTime? spentOn,
    double? hours,
  }) async {
    final api = _api;
    final e = _entriesByGuid[guid];
    if (api == null || e == null) return false;
    if (issueId != null && issueId != 0 && (issueSubject ?? '').isNotEmpty) {
      _issues[issueId] = _Issue(issueId, issueSubject!);
    }
    try {
      await api.updateTimeEntry(
        id: e.id,
        hours: hours,
        comments: description,
        activityId: activityId,
        issueId: issueId,
        spentOn: spentOn,
      );
      await refresh();
      return true;
    } on RedmineException catch (ex) {
      if (ex.kind == RedmineErrorKind.network) {
        await _queue.enqueue({
          'kind': 'update',
          'id': e.id,
          'hours': ?hours,
          'comments': description,
          'activityId': activityId,
          'issueId': issueId,
          if (spentOn != null) 'spentOn': spentOn.millisecondsSinceEpoch,
        });
        _emit(_onlineState, 1);
        _emit(_errors, const CoreError(
            message: 'Offline — your edit will sync when you reconnect.',
            userError: false));
        return true;
      }
      _reportError(ex);
      return false;
    }
  }

  /// Move/resize a completed entry's start/end (calendar drag → single PUT).
  Future<bool> setEntryTimes(String guid, {DateTime? start, DateTime? end}) =>
      updateEntry(guid: guid, start: start, end: end);

  // Legacy string setters from the FFI editor — unused by the new editor;
  // removed with the FFI cleanup slice.
  void edit(String guid, {bool editRunning = false, String focusedField = ''}) {}
  bool setDescription(String guid, String value) => false;
  bool setDuration(String guid, String value) => false;
  bool setStart(String guid, String value) => false;
  bool setEnd(String guid, String value) => false;
  bool setTags(String guid, String value) => false;
  bool setBillable(String guid, bool value) => false;

  // --- helpers ---

  void _emitLogin({required bool loggedIn, required int userId}) {
    final ev = LoginEvent(loggedIn: loggedIn, userId: userId);
    _lastLogin = ev;
    _emit(_loginState, ev);
    // Replay a browser deep link that arrived before login finished (cold
    // launch from the extension). The concurrent-mode setting is read from prefs
    // inside handleStartDeepLink, so nothing to capture here.
    if (loggedIn && _pendingLink != null) {
      final p = _pendingLink!;
      _pendingLink = null;
      unawaited(handleStartDeepLink(p.issueId, host: p.host));
    }
  }

  void _reportError(RedmineException e) {
    switch (e.kind) {
      case RedmineErrorKind.network:
        _emit(_onlineState, 1); // no network
        break;
      case RedmineErrorKind.auth:
      case RedmineErrorKind.generic:
      case RedmineErrorKind.notFound:
        break;
    }
    _emit(_errors, CoreError(message: e.message, userError: true));
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString(_kBaseUrl) ?? '';
    final da = prefs.getInt('default_activity_id');
    if (da != null && da > 0) {
      _defaultActivityId = da;
      _activityUserSet = true;
    }
    _sendCustomFields = prefs.getBool(_kCfSend) ?? true;
    _cfUserSet = prefs.getBool(_kCfUserSet) ?? false;
    _cfStart = prefs.getInt(_kCfStart) ?? _cfStart;
    _cfStop = prefs.getInt(_kCfStop) ?? _cfStop;
    _cfGuid = prefs.getInt(_kCfGuid) ?? _cfGuid;
    final key = await _readKey();
    if (_baseUrl.isNotEmpty && key != null && key.isNotEmpty) {
      unawaited(_doLogin(key)); // a later _persist migrates it into the keychain
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBaseUrl, _baseUrl);
    await _writeKey(_apiKey);
  }

  Future<void> _clearPersisted() async {
    await _deleteKey();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kApiKey); // clear any legacy plaintext copy too
  }

  void dispose() {
    _disposed = true;
    _running.clear();
    _stopTicker();
    _stopPoll();
    _api?.dispose();
    _timeEntries.close();
    _showLoadMore.close();
    _timerState.close();
    _runningEntries.close();
    _loginState.close();
    _errors.close();
    _onlineState.close();
    _reminders.close();
    _pomodoro.close();
    _idle.close();
    _syncEvents.close();
    _cfConfig.close();
    _cfAutoDisabled.close();
    _deepLinkNotices.close();
  }

  String _colorFor(int projectId) => projectColorHex(projectId);

  static String? _customField(List<dynamic>? cfs, int id) {
    if (cfs == null) return null;
    for (final f in cfs) {
      if (f is Map && (f['id'] as num?)?.toInt() == id) {
        final v = f['value'];
        return v is String ? v : null;
      }
    }
    return null;
  }

  static DateTime? _parse8601(String? s) {
    if (s == null || s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  static DateTime _synthStart(String? spentOn) {
    if (spentOn != null) {
      final d = DateTime.tryParse(spentOn);
      if (d != null) return DateTime(d.year, d.month, d.day, 9);
    }
    return DateTime.now();
  }

  static String _fmtDuration(int seconds) {
    final s = seconds.abs();
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = s % 60;
    return '$h:${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  static String _fmtClock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// ISO-8601 UTC seconds (`yyyy-MM-ddTHH:mm:ssZ`) — the toggl_start/stop shape.
  static String _isoZ(DateTime t) {
    final u = t.toUtc();
    return '${u.year.toString().padLeft(4, '0')}-${_two(u.month)}-${_two(u.day)}'
        'T${_two(u.hour)}:${_two(u.minute)}:${_two(u.second)}Z';
  }

  static final Random _rand = Random.secure();

  /// RFC-4122 v4 UUID for `toggl_guid` (write idempotency).
  static String _uuid() {
    final b = List<int>.generate(16, (_) => _rand.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((n) => n.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}'
        '-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static String _dayKey(DateTime t) =>
      '${t.year}-${t.month}-${t.day}';

  static const _weekdays = [
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'
  ];
  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];

  static String _dayLabel(DateTime t) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(t.year, t.month, t.day);
    final diff = today.difference(day).inDays;
    final date = '${_weekdays[t.weekday - 1]}, ${_months[t.month - 1]} ${t.day}';
    if (diff == 0) return 'Today · $date';
    if (diff == 1) return 'Yesterday · $date';
    return date;
  }
}

// --- internal value types ---

class _Project {
  _Project(this.id, this.name, this.color);
  final int id;
  final String name;
  final String color;
}

class _Issue {
  _Issue(this.id, this.subject);
  final int id;
  final String subject;
}

class _Entry {
  _Entry({
    required this.id,
    required this.guid,
    required this.pid,
    required this.tid,
    required this.activityId,
    required this.description,
    required this.start,
    required this.stop,
    required this.running,
  });
  final int id;
  final String guid;
  final int pid;
  final int tid;
  final int activityId;
  final String description;
  final DateTime start;
  final DateTime? stop;
  final bool running;
}

/// The single running entry (local-optimistic or discovered from Redmine).
class _RunningEntry {
  _RunningEntry({
    required this.guid,
    required this.redmineId,
    required this.issueId,
    required this.projectId,
    required this.activityId,
    required this.description,
    required this.start,
  });
  final String guid;
  int? redmineId;
  final int issueId;
  final int projectId;
  final int activityId;
  final String description;

  /// Mutable so the user can backdate a running timer (started tracking late) —
  /// see [RedmineService.adjustRunningStart].
  DateTime start;

  /// The in-flight create POST (resolves to the new id, or null on failure) so
  /// a fast stop can await it instead of posting a duplicate entry.
  Future<int?>? createFuture;

  /// Consecutive reconciles where this confirmed entry was *not* in the server's
  /// open set. Reset to 0 whenever it's seen open again; the entry is only
  /// dropped once this reaches `_missesToDrop`, so a single transient read-miss
  /// never flaps the running state to "stopped".
  int missStreak = 0;

  /// When [redmineId] was confirmed (start POST returned, or filled from a server
  /// match). A confirmed entry younger than `_dropGrace` is never dropped on a
  /// miss — the server may not have indexed it into the recent window yet.
  DateTime? confirmedAt;
}

/// A Redmine TimeEntryActivity (id + name) for the editor / settings pickers.
class Activity {
  const Activity(this.id, this.name);
  final int id;
  final String name;
}

/// Issue-picker search scope (design §3.7 segments).
enum IssueScope { mine, assigned, all }

/// A search result for the issue picker.
class IssueResult {
  const IssueResult({
    required this.id,
    required this.subject,
    required this.projectId,
    required this.projectName,
    required this.statusName,
    required this.closed,
  });
  final int id;
  final String subject;
  final int projectId;
  final String projectName;
  final String statusName;
  final bool closed;
}

// --- event types (same shapes the providers/UI already expect) ---

class LoginEvent {
  const LoginEvent({required this.loggedIn, required this.userId});
  final bool loggedIn;
  final int userId;
}

class CoreError {
  const CoreError({required this.message, required this.userError});
  final String message;
  final bool userError;
}

/// The toggl_* custom-field configuration: whether the fields are sent with
/// writes, and the three resolved/overridden ids. Drives Settings and the
/// simple-mode UI gating (calendar + per-entry timestamps).
class CustomFieldConfig {
  const CustomFieldConfig({
    required this.sendCustomFields,
    required this.startId,
    required this.stopId,
    required this.guidId,
  });
  final bool sendCustomFields;
  final int startId; // toggl_start
  final int stopId; // toggl_stop
  final int guidId; // toggl_guid (Redtick ID)
}

/// A one-shot "custom fields were auto-disabled" notice. Uses identity equality
/// (no custom `==`) so repeated notices with the same text still register as
/// distinct events — a `StreamProvider<String>` would dedupe equal AsyncValues
/// and only fire the alert once per session.
class CustomFieldNotice {
  CustomFieldNotice(this.message);
  final String message;
}

class Notice {
  const Notice(this.title, this.body);
  final String title;
  final String body;
}

/// What handling a `redtick://start` browser deep link resolved to.
enum DeepLinkOutcome {
  /// Single-timer mode: the timer was (re)started on the issue. UI: foreground +
  /// "Now tracking #N" toast.
  started,

  /// Multi-task mode: the issue was resolved but NOT started — the UI should
  /// foreground and ask before stacking a second timer.
  confirmConcurrent,

  /// A timer for the issue is already running — nothing to do.
  alreadyRunning,

  /// The link couldn't be honoured (wrong host, not logged in, issue not found).
  error,
}

/// The one-shot result of a `redtick://start` deep link. Like [CustomFieldNotice]
/// it uses identity equality (no `==`) so two identical outcomes — e.g. clicking
/// the same link twice — still fire distinct events instead of being deduped by
/// the `StreamProvider`.
class DeepLinkNotice {
  DeepLinkNotice.started({required this.issueId, required this.subject})
      : outcome = DeepLinkOutcome.started,
        projectId = 0,
        projectName = '',
        message = '';
  DeepLinkNotice.confirmConcurrent({
    required this.issueId,
    required this.subject,
    required this.projectId,
    required this.projectName,
  })  : outcome = DeepLinkOutcome.confirmConcurrent,
        message = '';
  DeepLinkNotice.alreadyRunning({required this.issueId, required this.subject})
      : outcome = DeepLinkOutcome.alreadyRunning,
        projectId = 0,
        projectName = '',
        message = 'Already tracking #$issueId.';
  DeepLinkNotice.error(this.message)
      : outcome = DeepLinkOutcome.error,
        issueId = 0,
        subject = '',
        projectId = 0,
        projectName = '';

  final DeepLinkOutcome outcome;
  final int issueId;
  final String subject;
  final int projectId;
  final String projectName;

  /// Human-readable text for the `error`/`alreadyRunning` toast (empty else).
  final String message;
}

class IdleNotice {
  const IdleNotice({
    required this.guid,
    required this.since,
    required this.duration,
    required this.started,
    required this.description,
  });
  final String guid;
  final String since;
  final String duration;
  final int started;
  final String description;
}

import 'dart:async';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/time_entry.dart';
import 'offline_queue.dart';
import 'redmine_api_client.dart';

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
  /// [httpClient] and [queue] are injectable for tests.
  static Future<RedmineService> create({
    http.Client? httpClient,
    OfflineQueue? queue,
  }) async {
    final s = RedmineService._()
      .._httpClient = httpClient
      .._queue = queue ?? OfflineQueue();
    await s._restore();
    return s;
  }

  http.Client? _httpClient;
  OfflineQueue _queue = OfflineQueue();

  // --- persisted config: base URL + settings in prefs; the API **key** in the
  //     OS keychain (flutter_secure_storage). Keychain calls are wrapped so a
  //     missing plugin (unit-test VM) or entitlement issue degrades gracefully
  //     (the key just isn't persisted) instead of crashing. ---
  static const _kBaseUrl = 'redmine_base_url';
  static const _kApiKey = 'redmine_api_key';
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

  final _projects = <int, _Project>{};
  final _issues = <int, _Issue>{};

  // Completed entries by display-guid (for continue/edit lookups), the recent
  // list (for a sensible default start), and the single running entry.
  final _entriesByGuid = <String, _Entry>{};
  List<_Entry> _recent = const [];
  _RunningEntry? _running;
  Timer? _ticker;
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
  final _loginState = StreamController<LoginEvent>.broadcast();
  final _errors = StreamController<CoreError>.broadcast();
  final _onlineState = StreamController<int>.broadcast();
  final _reminders = StreamController<Notice>.broadcast();
  final _pomodoro = StreamController<Notice>.broadcast();
  final _idle = StreamController<IdleNotice>.broadcast();

  LoginEvent? _lastLogin;
  List<TimeEntry>? _lastTimeEntries;
  TimeEntry? _lastTimer;

  Stream<List<TimeEntry>> get timeEntries => _timeEntries.stream;
  Stream<bool> get showLoadMore => _showLoadMore.stream;
  Stream<TimeEntry?> get timerState => _timerState.stream;
  Stream<LoginEvent> get loginState => _loginState.stream;
  Stream<CoreError> get errors => _errors.stream;
  Stream<int> get onlineState => _onlineState.stream;
  Stream<Notice> get reminders => _reminders.stream;
  Stream<Notice> get pomodoro => _pomodoro.stream;
  Stream<IdleNotice> get idle => _idle.stream;

  /// Replayed for late subscribers (the UI subscribes after startup events).
  LoginEvent? get currentLogin => _lastLogin;
  List<TimeEntry>? get currentTimeEntries => _lastTimeEntries;
  TimeEntry? get currentTimer => _lastTimer;

  List<Activity> get availableActivities => _activities;

  /// The activity name for [id] (empty if unknown) — for the timer/editor.
  String activityName(int id) {
    for (final a in _activities) {
      if (a.id == id) return a.name;
    }
    return '';
  }

  int get defaultActivityId => _defaultActivityId;

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
    _api?.dispose();
    _api = RedmineApiClient(
        baseUrl: _baseUrl, apiKey: apiKey, client: _httpClient);
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
    _api?.dispose();
    _api = null;
    _apiKey = '';
    _userId = 0;
    _projects.clear();
    _issues.clear();
    _lastTimeEntries = null;
    _lastTimer = null;
    unawaited(_clearPersisted());
    _emitLogin(loggedIn: false, userId: 0);
    return true;
  }

  /// Re-pull the account set and rebuild the list + running-timer state.
  Future<void> refresh() async {
    final api = _api;
    if (api == null) return;
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
      await _flushQueue(api); // network is back → replay any queued writes
    } on RedmineException catch (e) {
      _reportError(e);
    }
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
        if (name == 'toggl_start') {
          _cfStart = id;
          fStart = true;
        } else if (name == 'toggl_stop') {
          _cfStop = id;
          fStop = true;
        } else if (name == 'toggl_guid') {
          _cfGuid = id;
          fGuid = true;
        }
      }
    }

    for (final e in entries) {
      match(e['custom_fields'] as List?);
    }
    if (!(fStart && fStop && fGuid)) {
      final defs = await api.customFieldDefs();
      match(defs);
    }
  }

  // --- list building ---

  void _rebuild(List<Map<String, dynamic>> rawEntries) {
    final completed = <_Entry>[];
    _Entry? discovered; // an open (toggl_stop empty) entry from any device
    for (final rt in rawEntries) {
      final e = _mapEntry(rt);
      if (e == null) continue;
      if (e.running) {
        if (discovered == null || e.start.isAfter(discovered.start)) {
          discovered = e;
        }
      } else {
        completed.add(e);
      }
    }

    completed.sort((a, b) => b.start.compareTo(a.start));
    _recent = completed;
    _entriesByGuid
      ..clear()
      ..addEntries(completed.map((e) => MapEntry(_displayGuid(e), e)));

    _reconcileRunning(discovered);

    final list = _groupByDay(completed);
    _lastTimeEntries = list;
    _emit(_timeEntries, list);
    _emit(_showLoadMore, false);
  }

  /// Reconcile the server's open entry with any locally-started running entry
  /// (cross-device source of truth = the entry whose `toggl_stop` is empty).
  void _reconcileRunning(_Entry? discovered) {
    if (discovered != null) {
      final local = _running;
      if (local == null) {
        _running = _RunningEntry(
          guid: discovered.guid.isNotEmpty ? discovered.guid : _uuid(),
          redmineId: discovered.id,
          issueId: discovered.tid,
          projectId: discovered.pid,
          activityId: discovered.activityId,
          description: discovered.description,
          start: discovered.start,
        );
      } else if (local.guid == discovered.guid) {
        // Same entry round-tripped: keep the richer local instance (sub-second
        // start, in-memory edits) and only fill in the server id.
        local.redmineId ??= discovered.id;
      }
      // else: a different local running entry wins (don't clobber a fresh start
      // the server hasn't reflected yet).
    } else if (_running != null && _running!.redmineId != null) {
      // Confirmed entry no longer open on the server → stopped elsewhere.
      _running = null;
    }
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
      color: project?.color ?? '',
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
      color: project?.color ?? '',
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
  bool continueEntry(String guid) {
    final e = _entriesByGuid[guid];
    if (e == null) return false;
    unawaited(_startRunning(
      issueId: e.tid,
      projectId: e.pid,
      activityId: e.activityId,
      description: e.description,
    ));
    return true;
  }

  /// Start a timer against an explicitly-picked issue (from the issue picker).
  void startEntryForIssue({
    required int issueId,
    required int projectId,
    String subject = '',
    String projectName = '',
    String description = '',
    int? activityId,
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
    ));
  }

  bool stop() {
    unawaited(_stopRunning());
    return true;
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
    try {
      await api.createTimeEntry(
        issueId: issueId,
        projectId: projectId,
        hours: hours,
        spentOn: start,
        comments: description,
        activityId: activityId,
        togglStart: _isoZ(start),
        togglStop: _isoZ(end),
        togglGuid: guid,
        cfStart: _cfStart,
        cfStop: _cfStop,
        cfGuid: _cfGuid,
      );
      await refresh();
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
          'cfStart': _cfStart,
          'cfStop': _cfStop,
          'cfGuid': _cfGuid,
        });
        _emit(_onlineState, 1);
      } else {
        _reportError(e);
      }
    }
  }

  /// Trim the idle tail (stop at [idleStart]) and immediately resume the same
  /// issue with a fresh entry (idle prompt → "Discard & continue").
  void discardIdleAndContinue(DateTime idleStart) {
    final r = _running;
    if (r == null) return;
    final issueId = r.issueId;
    final projectId = r.projectId;
    final activityId = r.activityId;
    final description = r.description;
    unawaited(() async {
      await _stopRunning(at: idleStart);
      await _startRunning(
        issueId: issueId,
        projectId: projectId,
        activityId: activityId,
        description: description,
      );
    }());
  }

  Future<void> _startRunning({
    required int issueId,
    required int projectId,
    required int activityId,
    required String description,
  }) async {
    final api = _api;
    if (api == null) return;
    if (issueId <= 0 && projectId <= 0) {
      _emit(_errors, const CoreError(
          message: 'Pick an issue to start — use Continue (▶) on an entry.',
          userError: true));
      return;
    }
    if (_running != null) await _stopRunning();

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
    _running = entry;
    _emitRunning();

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
      if (_running?.guid == guid) _running!.redmineId = id;
      _emit(_onlineState, 0);
      return id;
    }).catchError((Object e) {
      if (e is RedmineException) _reportError(e);
      return null;
    });
    await entry.createFuture;
  }

  Future<void> _stopRunning({DateTime? at}) async {
    final api = _api;
    final r = _running;
    if (api == null || r == null) return;
    _running = null;
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
    try {
      if (id != null) {
        await api.updateTimeEntry(
          id: id,
          hours: hours,
          togglStop: _isoZ(stop),
          cfStop: _cfStop,
        );
      } else {
        // The start POST genuinely failed — create the finished entry now.
        await api.createTimeEntry(
          issueId: r.issueId,
          projectId: r.projectId,
          hours: hours,
          spentOn: r.start,
          comments: r.description,
          activityId: r.activityId,
          togglStart: _isoZ(r.start),
          togglStop: _isoZ(stop),
          togglGuid: r.guid,
          cfStart: _cfStart,
          cfStop: _cfStop,
          cfGuid: _cfGuid,
        );
      }
      await refresh();
    } on RedmineException catch (e) {
      if (e.kind == RedmineErrorKind.network) {
        await _queue.enqueue(id != null
            ? {
                'kind': 'update',
                'id': id,
                'hours': hours,
                'togglStop': _isoZ(stop),
                'cfStop': _cfStop,
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
                'cfStart': _cfStart,
                'cfStop': _cfStop,
                'cfGuid': _cfGuid,
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
    final r = _running;
    if (r == null) {
      _lastTimer = null;
      _emit(_timerState, null);
      _stopTicker();
    } else {
      _lastTimer = _runningModel(r);
      _emit(_timerState, _lastTimer);
      _startTicker();
    }
  }

  void _startTicker() {
    if (_disposed) return;
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
      final r = _running;
      if (r == null) {
        _stopTicker();
        return;
      }
      _lastTimer = _runningModel(r);
      _emit(_timerState, _lastTimer);
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
      await api.updateTimeEntry(
        id: e.id,
        hours: hours,
        comments: description,
        activityId: activityId,
        issueId: issueId,
        spentOn: newStart,
        togglStart: _isoZ(newStart),
        togglStop: _isoZ(newEnd),
        cfStart: _cfStart,
        cfStop: _cfStop,
      );
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
          'cfStart': _cfStart,
          'cfStop': _cfStop,
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
  }

  void _reportError(RedmineException e) {
    switch (e.kind) {
      case RedmineErrorKind.network:
        _emit(_onlineState, 1); // no network
        break;
      case RedmineErrorKind.auth:
      case RedmineErrorKind.generic:
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
    _running = null;
    _stopTicker();
    _api?.dispose();
    _timeEntries.close();
    _showLoadMore.close();
    _timerState.close();
    _loginState.close();
    _errors.close();
    _onlineState.close();
    _reminders.close();
    _pomodoro.close();
    _idle.close();
  }

  String _colorFor(int projectId) {
    const palette = [
      '#0b83d9', '#9e5bd9', '#d94182', '#e36a00', '#bf7000',
      '#2da608', '#06a893', '#c9806b', '#465bb3', '#990099',
    ];
    return palette[projectId % palette.length];
  }

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
  final DateTime start;

  /// The in-flight create POST (resolves to the new id, or null on failure) so
  /// a fast stop can await it instead of posting a duplicate entry.
  Future<int?>? createFuture;
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

class Notice {
  const Notice(this.title, this.body);
  final String title;
  final String body;
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

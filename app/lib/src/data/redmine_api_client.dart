import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Thin Dart client over the Redmine REST API — the native replacement for the
/// C++ core's `RedmineClient` (`src/redmine_client.cc`).
///
/// Auth: the Redmine API key is sent as the `X-Redmine-API-Key` header (the core
/// used basic-auth username == key; both are accepted by Redmine). All reads are
/// JSON; pagination mirrors the core's `redmineGetPaged` (limit=100 + offset,
/// stopping at `total_count` or an optional `maxItems` cap).
class RedmineApiClient {
  RedmineApiClient({
    required String baseUrl,
    required this.apiKey,
    http.Client? client,
  })  : _baseUrl = _normalizeBase(baseUrl),
        _client = client ?? http.Client();

  final String _baseUrl;
  final String apiKey;
  final http.Client _client;

  static const int _pageSize = 100;

  /// Cap the cached issue set (a dev can have thousands of open issues); live
  /// search reaches the rest. Mirrors `kMaxCachedIssues`.
  static const int maxCachedIssues = 500;

  /// ~30-day local time-entry retention (mirrors `kTimeEntryWindowDays`).
  static const int timeEntryWindowDays = 30;

  static String _normalizeBase(String url) {
    var u = url.trim();
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }

  String get baseUrl => _baseUrl;

  void dispose() => _client.close();

  // --- low-level ---

  Future<Map<String, dynamic>> _getJson(String relativeUrl) async {
    final uri = Uri.parse('$_baseUrl$relativeUrl');
    final http.Response resp;
    try {
      // followRedirects=false: surface a 3xx as an error (don't silently follow
      // to a different host and leak the API key) — the host must be exact.
      final req = http.Request('GET', uri)
        ..followRedirects = false
        ..headers['X-Redmine-API-Key'] = apiKey
        ..headers['Accept'] = 'application/json';
      final streamed =
          await _client.send(req).timeout(const Duration(seconds: 20));
      resp = await http.Response.fromStream(streamed);
    } on SocketException catch (e) {
      throw RedmineException.network('Cannot reach ${uri.host}: ${e.message}');
    } on HttpException catch (e) {
      throw RedmineException.network('Network error: ${e.message}');
    } on FormatException catch (e) {
      throw RedmineException('Bad URL: ${e.message}');
    }

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw RedmineException.auth(
          'Unauthorized (${resp.statusCode}) — check the API key.');
    }
    if (resp.statusCode >= 300 && resp.statusCode < 400) {
      throw RedmineException(
          'Host redirected (${resp.statusCode}) — use the exact Redmine URL '
          '(no redirect).');
    }
    if (resp.statusCode >= 400) {
      throw RedmineException('Redmine HTTP ${resp.statusCode} for $relativeUrl');
    }
    try {
      final decoded = jsonDecode(resp.body);
      if (decoded is Map<String, dynamic>) return decoded;
      throw RedmineException('Unexpected JSON shape for $relativeUrl');
    } on FormatException {
      throw RedmineException('Failed to parse response for $relativeUrl');
    }
  }

  /// GET every page of a Redmine collection, concatenating each page's
  /// [arrayKey] array. [query] is the extra query string (without limit/offset).
  Future<List<Map<String, dynamic>>> _getPaged(
    String path,
    String query,
    String arrayKey, {
    int maxItems = 0,
  }) async {
    final out = <Map<String, dynamic>>[];
    var offset = 0;
    while (true) {
      var pageLimit = _pageSize;
      if (maxItems > 0) {
        final remaining = maxItems - out.length;
        pageLimit = remaining < _pageSize ? remaining : _pageSize;
        if (pageLimit < 1) break;
      }
      final parts = <String>[
        if (query.isNotEmpty) query,
        'limit=$pageLimit',
        'offset=$offset',
      ];
      final root = await _getJson('$path?${parts.join('&')}');
      final arr = (root[arrayKey] as List?) ?? const [];
      for (final item in arr) {
        if (item is Map<String, dynamic>) out.add(item);
      }
      final total = (root['total_count'] as num?)?.toInt() ?? arr.length;
      offset += arr.length;
      if (maxItems > 0 && out.length >= maxItems) {
        if (out.length > maxItems) out.length = maxItems;
        break;
      }
      if (arr.isEmpty || offset >= total) break;
    }
    return out;
  }

  // --- account-load reads (mirror FetchAccountJSON) ---

  /// `GET /users/current.json` → the `user` object. Validates the key.
  Future<Map<String, dynamic>> currentUser() async {
    final root = await _getJson('/users/current.json');
    final user = root['user'];
    if (user is! Map<String, dynamic> || (user['id'] as num?) == null) {
      throw RedmineException('Redmine: /users/current returned no user id');
    }
    return user;
  }

  /// All projects (unbounded, paged).
  Future<List<Map<String, dynamic>>> projects() =>
      _getPaged('/projects.json', '', 'projects');

  /// My open issues, most-recently-updated first, capped at [maxCachedIssues].
  Future<List<Map<String, dynamic>>> myOpenIssues() => _getPaged(
        '/issues.json',
        'assigned_to_id=me&status_id=open&sort=updated_on:desc',
        'issues',
        maxItems: maxCachedIssues,
      );

  /// My time entries within the retention window.
  Future<List<Map<String, dynamic>>> recentTimeEntries() {
    final from = DateTime.now().subtract(
        const Duration(days: timeEntryWindowDays));
    final fromStr =
        '${from.year.toString().padLeft(4, '0')}-${_two(from.month)}-${_two(from.day)}';
    return _getPaged(
        '/time_entries.json', 'user_id=me&from=$fromStr', 'time_entries');
  }

  /// The instance's activity enumeration (`time_entry_activities`).
  Future<List<Map<String, dynamic>>> activities() async {
    final root = await _getJson('/enumerations/time_entry_activities.json');
    return ((root['time_entry_activities'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();
  }

  /// Custom-field definitions (admin-only on some instances → returns null on
  /// 401/403 so the caller falls back to learning ids from the user's entries).
  Future<List<Map<String, dynamic>>?> customFieldDefs() async {
    try {
      final root = await _getJson('/custom_fields.json');
      return ((root['custom_fields'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList();
    } on RedmineException catch (e) {
      if (e.kind == RedmineErrorKind.auth) return null;
      rethrow;
    }
  }

  /// Find issues for the picker. [query] (all-digits → `issue_id`, else
  /// `subject=~`) is combined with a [scope] filter (e.g.
  /// `assigned_to_id=me&status_id=open` or `status_id=*`). Mirrors the C core's
  /// `SearchIssuesJSON` but with a configurable scope.
  Future<List<Map<String, dynamic>>> findIssues({
    String query = '',
    required String scope,
    int maxItems = 50,
  }) {
    final parts = <String>[];
    final q = query.trim();
    if (q.isNotEmpty) {
      // URL-encode the free-text value so '#', '&', '+', spaces, accents etc.
      // don't corrupt the query (the C core's SearchIssuesJSON encoded too).
      parts.add(RegExp(r'^\d+$').hasMatch(q)
          ? 'issue_id=$q'
          : 'subject=~${Uri.encodeQueryComponent(q)}');
    }
    parts.add(scope);
    return _getPaged('/issues.json', parts.join('&'), 'issues',
        maxItems: maxItems);
  }

  // --- writes (time entries) ---

  /// `POST /time_entries.json`. Returns the new Redmine time-entry id.
  /// Pass [togglStop] = null/'' for a *running* entry (open `toggl_stop`).
  Future<int> createTimeEntry({
    required int issueId,
    required int projectId,
    required double hours,
    required DateTime spentOn,
    required String comments,
    required int activityId,
    required String togglStart,
    required String togglStop,
    required String togglGuid,
    required int cfStart,
    required int cfStop,
    required int cfGuid,
  }) async {
    final body = <String, dynamic>{
      'time_entry': {
        if (issueId > 0) 'issue_id': issueId,
        if (issueId <= 0 && projectId > 0) 'project_id': projectId,
        'hours': hours,
        'spent_on': _date(spentOn),
        'comments': comments,
        'activity_id': activityId,
        'custom_fields': [
          {'id': cfStart, 'value': togglStart},
          {'id': cfStop, 'value': togglStop},
          {'id': cfGuid, 'value': togglGuid},
        ],
      },
    };
    final root = await _send('POST', '/time_entries.json', body);
    final te = root?['time_entry'];
    final id = (te is Map ? te['id'] as num? : null)?.toInt();
    if (id == null) {
      throw RedmineException('Create time entry: no id in response');
    }
    return id;
  }

  /// `PUT /time_entries/{id}.json` — finalize hours + set the toggl_stop CF.
  Future<void> updateTimeEntry({
    required int id,
    double? hours,
    String? comments,
    int? activityId,
    int? issueId,
    DateTime? spentOn,
    String? togglStart,
    String? togglStop,
    int cfStart = 0,
    int cfStop = 0,
  }) async {
    final cfs = <Map<String, dynamic>>[
      if (togglStart != null && cfStart > 0)
        {'id': cfStart, 'value': togglStart},
      if (togglStop != null && cfStop > 0) {'id': cfStop, 'value': togglStop},
    ];
    final te = <String, dynamic>{};
    if (hours != null) te['hours'] = hours;
    if (comments != null) te['comments'] = comments;
    if (activityId != null) te['activity_id'] = activityId;
    if (issueId != null) te['issue_id'] = issueId;
    if (spentOn != null) te['spent_on'] = _date(spentOn);
    if (cfs.isNotEmpty) te['custom_fields'] = cfs;
    await _send('PUT', '/time_entries/$id.json', {'time_entry': te});
  }

  /// `DELETE /time_entries/{id}.json`.
  Future<void> deleteTimeEntry(int id) async {
    await _send('DELETE', '/time_entries/$id.json', null);
  }

  /// Send a write request; returns the parsed JSON body (or null for an empty
  /// 204 response, which Redmine returns for PUT/DELETE).
  Future<Map<String, dynamic>?> _send(
      String method, String relativeUrl, Map<String, dynamic>? body) async {
    final uri = Uri.parse('$_baseUrl$relativeUrl');
    final req = http.Request(method, uri)
      ..followRedirects = false
      ..headers['X-Redmine-API-Key'] = apiKey
      ..headers['Accept'] = 'application/json';
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      req.body = jsonEncode(body);
    }
    final http.StreamedResponse streamed;
    try {
      streamed =
          await _client.send(req).timeout(const Duration(seconds: 20));
    } on SocketException catch (e) {
      throw RedmineException.network('Cannot reach ${uri.host}: ${e.message}');
    }
    final resp = await http.Response.fromStream(streamed);
    if (resp.statusCode == 401 || resp.statusCode == 403) {
      throw RedmineException.auth('Unauthorized (${resp.statusCode}).');
    }
    if (resp.statusCode >= 300 && resp.statusCode < 400) {
      throw RedmineException(
          'Host redirected (${resp.statusCode}) — use the exact Redmine URL.');
    }
    if (resp.statusCode == 422) {
      throw RedmineException('Redmine rejected the entry: ${resp.body}');
    }
    if (resp.statusCode >= 400) {
      throw RedmineException(
          'Redmine HTTP ${resp.statusCode} for $method $relativeUrl');
    }
    if (resp.body.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(resp.body);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String _date(DateTime t) =>
      '${t.year.toString().padLeft(4, '0')}-${_two(t.month)}-${_two(t.day)}';

  static String _two(int n) => n.toString().padLeft(2, '0');
}

enum RedmineErrorKind { generic, auth, network }

/// A Redmine API failure, carrying a kind so the service can map it to the
/// right `onlineState` / inline error.
class RedmineException implements Exception {
  RedmineException(this.message, [this.kind = RedmineErrorKind.generic]);
  RedmineException.auth(this.message) : kind = RedmineErrorKind.auth;
  RedmineException.network(this.message) : kind = RedmineErrorKind.network;

  final String message;
  final RedmineErrorKind kind;

  @override
  String toString() => message;
}

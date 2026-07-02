@TestOn('vm')
library;

// RedmineService.handleStartDeepLink — the browser-extension `redtick://start`
// flow — against a stateful mock backend:
//  - allowConcurrent false  → starts the timer (one POST) + a `started` notice
//  - allowConcurrent true   → a `confirmConcurrent` notice, NOTHING started
//  - a host that isn't ours → an `error` notice, nothing started
//  - an unknown issue       → an `error` notice
//  - the issue already runs → an `alreadyRunning` notice, no second POST
//  - a link before login    → an `error`, then it replays as `started` on login

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:redtick/src/data/redmine_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A backend that knows one issue (#23409 in project 75). `/issues.json` honours
/// the `issue_id` filter so unknown ids resolve to "not found". Time entries are
/// stored so a POST'd open entry stays running across the post-start reconcile.
http.Client deepLinkBackend(
  List<Map<String, dynamic>> store, {
  List<Map<String, dynamic>>? posts,
}) {
  var nextId = 4000;
  http.Response j(Object o, [int s = 200]) => http.Response(jsonEncode(o), s,
      headers: {'content-type': 'application/json'});
  Map<String, dynamic>? byId(int id) {
    for (final e in store) {
      if (e['id'] == id) return e;
    }
    return null;
  }

  Map<String, dynamic> demoIssue() => {
        'id': 23409,
        'subject': 'Demo issue',
        'project': {'id': 75, 'name': 'SUMA'},
        'status': {'name': 'In Progress', 'is_closed': false},
      };

  return MockClient((req) async {
    final p = req.url.path;
    final qp = req.url.queryParameters;
    if (req.method == 'GET') {
      if (p.endsWith('/users/current.json')) {
        return j({
          'user': {'id': 9, 'mail': 'me@x.cz', 'firstname': 'Me', 'lastname': ''}
        });
      }
      if (p.endsWith('/projects.json')) {
        return j({
          'projects': [
            {'id': 75, 'name': 'SUMA', 'status': 1}
          ],
          'total_count': 1
        });
      }
      if (p.endsWith('/time_entry_activities.json')) {
        return j({
          'time_entry_activities': [
            {'id': 6, 'name': 'Development', 'is_default': true, 'active': true}
          ]
        });
      }
      if (p.endsWith('/custom_fields.json')) {
        return j({
          'custom_fields': [
            {'id': 12, 'name': 'toggl_start', 'customized_type': 'time_entry'},
            {'id': 14, 'name': 'toggl_stop', 'customized_type': 'time_entry'},
            {'id': 13, 'name': 'toggl_guid', 'customized_type': 'time_entry'},
          ]
        });
      }
      final m = RegExp(r'/time_entries/(\d+)\.json').firstMatch(p);
      if (m != null) {
        final e = byId(int.parse(m.group(1)!));
        return e == null ? http.Response('not found', 404) : j({'time_entry': e});
      }
      if (p.endsWith('/time_entries.json')) {
        return j({'time_entries': store, 'total_count': store.length});
      }
      if (p.endsWith('/issues.json')) {
        // Deep-link lookups filter by issue_id; only #23409 exists. The no-filter
        // "my open issues" pull (login refresh) returns nothing.
        final list = qp['issue_id'] == '23409'
            ? [demoIssue()]
            : const <Map<String, dynamic>>[];
        return j({'issues': list, 'total_count': list.length});
      }
    }
    if (req.method == 'POST' && p.endsWith('/time_entries.json')) {
      final body =
          (jsonDecode(req.body) as Map)['time_entry'] as Map<String, dynamic>;
      posts?.add(body);
      final cfs = (body['custom_fields'] as List?)?.cast<Map>() ?? const [];
      String cf(int id) => (cfs.firstWhere((c) => c['id'] == id,
          orElse: () => {'value': ''})['value'] as String);
      final id = nextId++;
      store.add({
        'id': id,
        'project': {'id': body['project_id'] ?? 75},
        'issue': {'id': body['issue_id'] ?? 23409},
        'activity': {'id': body['activity_id'] ?? 6},
        'comments': body['comments'] ?? '',
        'hours': (body['hours'] as num?) ?? 0,
        'spent_on': '2026-06-25',
        'custom_fields': [
          {'id': 12, 'name': 'toggl_start', 'value': cf(12)},
          {'id': 14, 'name': 'toggl_stop', 'value': cf(14)},
          {'id': 13, 'name': 'toggl_guid', 'value': cf(13)},
        ],
      });
      return j({
        'time_entry': {'id': id}
      }, 201);
    }
    if (req.method == 'PUT') {
      return http.Response('', 204);
    }
    return http.Response('not found', 404);
  });
}

Future<RedmineService> loggedInService(http.Client client) async {
  final svc = await RedmineService.create(httpClient: client);
  final ready = svc.loginState.firstWhere((e) => e.loggedIn);
  svc.setBaseUrl('https://x');
  svc.login('', 'key');
  await ready.timeout(const Duration(seconds: 5));
  return svc;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('single-timer mode: starts the issue and emits `started`', () async {
    final store = <Map<String, dynamic>>[];
    final posts = <Map<String, dynamic>>[];
    final svc = await loggedInService(deepLinkBackend(store, posts: posts));
    addTearDown(svc.dispose);

    final started = svc.deepLinkNotices
        .firstWhere((n) => n.outcome == DeepLinkOutcome.started);
    await svc.handleStartDeepLink(23409);
    final n = await started.timeout(const Duration(seconds: 5));
    expect(n.issueId, 23409);
    expect(n.subject, 'Demo issue');

    await svc.runningEntries
        .firstWhere((l) => l.where((e) => e.isRunning).length == 1)
        .timeout(const Duration(seconds: 5));
    expect(posts, hasLength(1), reason: 'started → one open entry POSTed');
  });

  test('multi-task mode: emits `confirmConcurrent` and starts NOTHING',
      () async {
    // The multi-task setting is read from prefs by the handler.
    SharedPreferences.setMockInitialValues({'allow_concurrent_tracking': true});
    final store = <Map<String, dynamic>>[];
    final posts = <Map<String, dynamic>>[];
    final svc = await loggedInService(deepLinkBackend(store, posts: posts));
    addTearDown(svc.dispose);

    final confirm = svc.deepLinkNotices
        .firstWhere((n) => n.outcome == DeepLinkOutcome.confirmConcurrent);
    await svc.handleStartDeepLink(23409);
    final n = await confirm.timeout(const Duration(seconds: 5));
    expect(n.issueId, 23409);
    expect(n.subject, 'Demo issue');
    expect(n.projectId, 75);

    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(posts, isEmpty, reason: 'the UI must confirm before anything starts');
    expect(svc.currentRunningEntries.where((e) => e.isRunning), isEmpty);
  });

  test('host guard: a foreign host errors; the matching host starts', () async {
    final store = <Map<String, dynamic>>[];
    final posts = <Map<String, dynamic>>[];
    final svc = await loggedInService(deepLinkBackend(store, posts: posts));
    addTearDown(svc.dispose);

    final err = svc.deepLinkNotices
        .firstWhere((n) => n.outcome == DeepLinkOutcome.error);
    await svc.handleStartDeepLink(23409,
        host: 'other.example.com');
    final e = await err.timeout(const Duration(seconds: 5));
    expect(e.message, contains('different Redmine'));
    expect(posts, isEmpty);

    // The logged-in host is `x` (from https://x) → a matching link proceeds.
    final started = svc.deepLinkNotices
        .firstWhere((n) => n.outcome == DeepLinkOutcome.started);
    await svc.handleStartDeepLink(23409, host: 'x');
    await started.timeout(const Duration(seconds: 5));
    await svc.runningEntries
        .firstWhere((l) => l.where((en) => en.isRunning).length == 1)
        .timeout(const Duration(seconds: 5));
    expect(posts, hasLength(1));
  });

  test('unknown issue → `error`', () async {
    final store = <Map<String, dynamic>>[];
    final posts = <Map<String, dynamic>>[];
    final svc = await loggedInService(deepLinkBackend(store, posts: posts));
    addTearDown(svc.dispose);

    final err = svc.deepLinkNotices
        .firstWhere((n) => n.outcome == DeepLinkOutcome.error);
    await svc.handleStartDeepLink(99999);
    final e = await err.timeout(const Duration(seconds: 5));
    expect(e.message, contains('#99999'));
    expect(posts, isEmpty);
  });

  test('already tracking that issue → `alreadyRunning`, no second POST',
      () async {
    final store = <Map<String, dynamic>>[];
    final posts = <Map<String, dynamic>>[];
    final svc = await loggedInService(deepLinkBackend(store, posts: posts));
    addTearDown(svc.dispose);

    svc.startEntryForIssue(issueId: 23409, projectId: 75, subject: 'Demo issue');
    await svc.runningEntries
        .firstWhere((l) => l.where((e) => e.isRunning).length == 1)
        .timeout(const Duration(seconds: 5));
    expect(posts, hasLength(1));

    final again = svc.deepLinkNotices
        .firstWhere((n) => n.outcome == DeepLinkOutcome.alreadyRunning);
    await svc.handleStartDeepLink(23409);
    final n = await again.timeout(const Duration(seconds: 5));
    expect(n.issueId, 23409);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(posts, hasLength(1), reason: 'no duplicate timer for a running issue');
  });

  test('cold launch before login: errors, then replays as `started` on login',
      () async {
    final store = <Map<String, dynamic>>[];
    final posts = <Map<String, dynamic>>[];
    final client = deepLinkBackend(store, posts: posts);
    // Not logged in (empty prefs → no auto-login).
    final svc = await RedmineService.create(httpClient: client);
    addTearDown(svc.dispose);

    final err = svc.deepLinkNotices
        .firstWhere((n) => n.outcome == DeepLinkOutcome.error);
    await svc.handleStartDeepLink(23409);
    final e = await err.timeout(const Duration(seconds: 5));
    expect(e.message, contains('Log in'));
    expect(posts, isEmpty);

    // Now log in → the queued link replays automatically.
    final started = svc.deepLinkNotices
        .firstWhere((n) => n.outcome == DeepLinkOutcome.started);
    svc.setBaseUrl('https://x');
    svc.login('', 'key');
    final n = await started.timeout(const Duration(seconds: 5));
    expect(n.issueId, 23409);
    await svc.runningEntries
        .firstWhere((l) => l.where((en) => en.isRunning).length == 1)
        .timeout(const Duration(seconds: 5));
    expect(posts, hasLength(1));
  });

  test('queued link replays with the PERSISTED multi-task setting, not a '
      'stale one', () async {
    // Regression guard for the cold-launch race: a link queued before login must
    // honour the persisted "multi-task ON" pref on replay (→ confirmConcurrent),
    // not a value captured while the setting notifier was still defaulting.
    SharedPreferences.setMockInitialValues({'allow_concurrent_tracking': true});
    final store = <Map<String, dynamic>>[];
    final posts = <Map<String, dynamic>>[];
    final client = deepLinkBackend(store, posts: posts);
    final svc = await RedmineService.create(httpClient: client);
    addTearDown(svc.dispose);

    final err = svc.deepLinkNotices
        .firstWhere((n) => n.outcome == DeepLinkOutcome.error);
    await svc.handleStartDeepLink(23409);
    await err.timeout(const Duration(seconds: 5));

    final confirm = svc.deepLinkNotices
        .firstWhere((n) => n.outcome == DeepLinkOutcome.confirmConcurrent);
    svc.setBaseUrl('https://x');
    svc.login('', 'key');
    final n = await confirm.timeout(const Duration(seconds: 5));
    expect(n.issueId, 23409);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(posts, isEmpty, reason: 'ON path must await confirmation');
  });
}

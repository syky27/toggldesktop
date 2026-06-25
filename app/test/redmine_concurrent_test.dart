@TestOn('vm')
library;

// Concurrent (multi-task) tracking against a *stateful* mock Redmine backend:
// POSTed open entries are persisted and returned on later GETs, so the
// reconcile that runs after each stop faithfully keeps the other timers alive.
//  - two stopOthers:false starts → two open entries stack
//  - collapseRunningToMostRecent() keeps the newest, stops the rest
//  - stopEntry(guid) finalizes one specific timer

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:redtick/src/data/redmine_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A backend whose `/time_entries` collection is mutable: POST appends an entry
/// (open while its toggl_stop is empty), PUT updates an entry's toggl_stop, and
/// GET returns the live collection — so cross-device reconcile behaves for real.
http.Client statefulBackend(
  List<Map<String, dynamic>> store, {
  List<Map<String, dynamic>>? posts,
  List<Map<String, dynamic>>? puts,
}) {
  var nextId = 3000;
  http.Response j(Object o, [int s = 200]) => http.Response(jsonEncode(o), s,
      headers: {'content-type': 'application/json'});
  Map<String, dynamic>? byId(int id) {
    for (final e in store) {
      if (e['id'] == id) return e;
    }
    return null;
  }

  return MockClient((req) async {
    final p = req.url.path;
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
      if (p.endsWith('/issues.json')) {
        return j({
          'issues': [
            {
              'id': 23409,
              'subject': 'Demo issue',
              'project': {'id': 75, 'name': 'SUMA'},
              'status': {'name': 'In Progress', 'is_closed': false},
            }
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
        return e == null
            ? http.Response('not found', 404)
            : j({'time_entry': e});
      }
      if (p.endsWith('/time_entries.json')) {
        return j({'time_entries': store, 'total_count': store.length});
      }
    }
    if (req.method == 'POST' && p.endsWith('/time_entries.json')) {
      final body =
          (jsonDecode(req.body) as Map)['time_entry'] as Map<String, dynamic>;
      posts?.add(body);
      final cfs = (body['custom_fields'] as List).cast<Map>();
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
      final m = RegExp(r'/time_entries/(\d+)\.json').firstMatch(p);
      final body =
          (jsonDecode(req.body) as Map)['time_entry'] as Map<String, dynamic>;
      puts?.add(body);
      if (m != null) {
        final e = byId(int.parse(m.group(1)!));
        if (e != null) {
          if (body['hours'] != null) e['hours'] = body['hours'];
          final cfs = body['custom_fields'];
          if (cfs is List) {
            for (final c in cfs.cast<Map>()) {
              if (c['id'] == 14) {
                (e['custom_fields'] as List)
                    .cast<Map>()
                    .firstWhere((x) => x['id'] == 14)['value'] = c['value'];
              }
            }
          }
        }
      }
      return http.Response('', 204);
    }
    return http.Response('not found', 404);
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('two concurrent starts stack; collapse keeps newest; stopEntry clears',
      () async {
    final store = <Map<String, dynamic>>[];
    final posts = <Map<String, dynamic>>[];
    final puts = <Map<String, dynamic>>[];
    final svc = await RedmineService.create(
        httpClient: statefulBackend(store, posts: posts, puts: puts));
    addTearDown(svc.dispose);
    final loggedIn = svc.loginState.firstWhere((e) => e.loggedIn);
    svc.setBaseUrl('https://x');
    svc.login('', 'key');
    await loggedIn.timeout(const Duration(seconds: 5));

    // Start two timers without stopping each other.
    final twoRunning = svc.runningEntries
        .firstWhere((l) => l.where((e) => e.isRunning).length == 2);
    svc.startEntryForIssue(
        issueId: 23409, projectId: 75, description: 'A', stopOthers: false);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    svc.startEntryForIssue(
        issueId: 23409, projectId: 75, description: 'B', stopOthers: false);

    final two = (await twoRunning.timeout(const Duration(seconds: 5)))
        .where((e) => e.isRunning)
        .toList();
    expect(two, hasLength(2));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(posts, hasLength(2),
        reason: 'each concurrent start POSTs its own open entry');
    // Sorted oldest-first → the most recently started (B) is last.
    expect(two.last.description, 'B');

    // Collapse → keep the newest (B), stop the rest.
    final oneRunning = svc.runningEntries
        .firstWhere((l) => l.where((e) => e.isRunning).length == 1);
    svc.collapseRunningToMostRecent();
    final one = (await oneRunning.timeout(const Duration(seconds: 5)))
        .where((e) => e.isRunning)
        .toList();
    expect(one.map((e) => e.description), ['B']);

    // Stop the survivor by guid → nothing running.
    final noneRunning = svc.runningEntries
        .firstWhere((l) => l.where((e) => e.isRunning).isEmpty);
    svc.stopEntry(one.first.guid);
    final none = await noneRunning.timeout(const Duration(seconds: 5));
    expect(none.where((e) => e.isRunning), isEmpty);
  });

  test('default stopOthers replaces the running timer (single-timer mode)',
      () async {
    final store = <Map<String, dynamic>>[];
    final svc = await RedmineService.create(
        httpClient: statefulBackend(store));
    addTearDown(svc.dispose);
    final loggedIn = svc.loginState.firstWhere((e) => e.loggedIn);
    svc.setBaseUrl('https://x');
    svc.login('', 'key');
    await loggedIn.timeout(const Duration(seconds: 5));

    svc.startEntryForIssue(issueId: 23409, projectId: 75, description: 'A');
    await svc.runningEntries
        .firstWhere((l) => l.where((e) => e.isRunning).length == 1)
        .timeout(const Duration(seconds: 5));
    // Default start (stopOthers: true) → still only one running.
    svc.startEntryForIssue(issueId: 23409, projectId: 75, description: 'B');
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final list = svc.currentRunningEntries.where((e) => e.isRunning).toList();
    expect(list, hasLength(1));
    expect(list.single.description, 'B');
  });
}

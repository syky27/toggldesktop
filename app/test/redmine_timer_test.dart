@TestOn('vm')
library;

// Deterministic Slice 1 logic against a mock Redmine backend (no real writes):
//  - cross-device discovery: an entry with empty toggl_stop shows as running
//  - continue -> POST an open entry (toggl_stop="") -> stop -> PUT finalize

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:redtick/src/data/redmine_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

http.Client backend({
  List<Map<String, dynamic>> timeEntries = const [],
  List<Map<String, dynamic>>? posts,
  List<Map<String, dynamic>>? puts,
  List<int>? deletes,
  int postDelayMs = 0,
}) {
  var nextId = 2000;
  http.Response j(Object o, [int s = 200]) =>
      http.Response(jsonEncode(o), s, headers: {'content-type': 'application/json'});
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
      if (p.endsWith('/time_entries.json')) {
        return j({'time_entries': timeEntries, 'total_count': timeEntries.length});
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
    }
    if (req.method == 'POST' && p.endsWith('/time_entries.json')) {
      if (postDelayMs > 0) {
        await Future<void>.delayed(Duration(milliseconds: postDelayMs));
      }
      posts?.add((jsonDecode(req.body) as Map)['time_entry'] as Map<String, dynamic>);
      return j({
        'time_entry': {'id': nextId++}
      }, 201);
    }
    if (req.method == 'PUT') {
      puts?.add((jsonDecode(req.body) as Map)['time_entry'] as Map<String, dynamic>);
      return http.Response('', 204);
    }
    if (req.method == 'DELETE') {
      final m = RegExp(r'/time_entries/(\d+)\.json').firstMatch(p);
      if (m != null) deletes?.add(int.parse(m.group(1)!));
      return http.Response('', 204);
    }
    return http.Response('not found', 404);
  });
}

Map<String, dynamic> entry({
  required int id,
  required String start,
  required String stop,
  String guid = '',
  String comments = '',
}) =>
    {
      'id': id,
      'project': {'id': 75},
      'issue': {'id': 23409},
      'activity': {'id': 6},
      'comments': comments,
      'hours': 0.5,
      'spent_on': '2026-06-25',
      'custom_fields': [
        {'id': 12, 'name': 'toggl_start', 'value': start},
        {'id': 14, 'name': 'toggl_stop', 'value': stop},
        {'id': 13, 'name': 'toggl_guid', 'value': guid},
      ],
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('discovers a cross-device running entry (empty toggl_stop)', () async {
    final open = entry(
        id: 1500,
        start: '2026-06-25T08:00:00Z',
        stop: '',
        guid: 'abc',
        comments: 'cross-device');
    final svc = await RedmineService.create(
        httpClient: backend(timeEntries: [open]));
    addTearDown(svc.dispose);

    final running = svc.timerState.firstWhere((t) => t != null && t.isRunning);
    svc.setBaseUrl('https://x');
    svc.login('', 'key');

    final t = await running.timeout(const Duration(seconds: 5));
    expect(t!.isRunning, isTrue);
    expect(t.taskLabel, contains('23409'));
  });

  test('continue posts an open entry, stop finalizes it', () async {
    final posts = <Map<String, dynamic>>[];
    final puts = <Map<String, dynamic>>[];
    final done = entry(
        id: 1400,
        start: '2026-06-25T07:00:00Z',
        stop: '2026-06-25T08:00:00Z',
        guid: 'past-guid',
        comments: 'past');
    final svc = await RedmineService.create(
        httpClient: backend(timeEntries: [done], posts: posts, puts: puts));
    addTearDown(svc.dispose);

    final firstList =
        svc.timeEntries.firstWhere((l) => l.any((e) => !e.isHeader));
    svc.setBaseUrl('https://x');
    svc.login('', 'key');
    final list = await firstList.timeout(const Duration(seconds: 5));
    final row = list.firstWhere((e) => !e.isHeader);

    // Continue → optimistic running + POST.
    final running = svc.timerState.firstWhere((t) => t != null && t.isRunning);
    expect(svc.continueEntry(row.guid), isTrue);
    final t = await running.timeout(const Duration(seconds: 5));
    expect(t!.isRunning, isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(posts, hasLength(1));
    final post = posts.first;
    expect(post['issue_id'], 23409);
    expect((post['hours'] as num).toDouble(), 0.0);
    final cfs = (post['custom_fields'] as List).cast<Map>();
    String cf(int id) => cfs.firstWhere((c) => c['id'] == id)['value'] as String;
    expect(cf(12), isNotEmpty); // toggl_start set
    expect(cf(14), isEmpty); // toggl_stop EMPTY → running
    expect(cf(13), isNotEmpty); // toggl_guid set

    // Stop → null timer + PUT finalize.
    final stopped = svc.timerState.firstWhere((t) => t == null);
    expect(svc.stop(), isTrue);
    await stopped.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 80));

    expect(puts, hasLength(1));
    final put = puts.first;
    expect((put['hours'] as num).toDouble(), greaterThanOrEqualTo(0.0));
    final putCfs = (put['custom_fields'] as List).cast<Map>();
    expect(
        putCfs.any(
            (c) => c['id'] == 14 && (c['value'] as String).isNotEmpty),
        isTrue); // toggl_stop now set
  });

  test('searchIssues parses id/subject/project/status', () async {
    final svc = await RedmineService.create(httpClient: backend());
    addTearDown(svc.dispose);
    final loggedIn = svc.loginState.firstWhere((e) => e.loggedIn);
    svc.setBaseUrl('https://x');
    svc.login('', 'key');
    await loggedIn.timeout(const Duration(seconds: 5));
    final res = await svc.searchIssues(query: 'demo', scope: IssueScope.all);
    expect(res, hasLength(1));
    expect(res.first.id, 23409);
    expect(res.first.subject, 'Demo issue');
    expect(res.first.projectName, 'SUMA');
    expect(res.first.statusName, 'In Progress');
    expect(res.first.closed, isFalse);
  });

  test('updateEntry PUTs comments + activity + hours + spent_on', () async {
    final puts = <Map<String, dynamic>>[];
    final done = entry(
        id: 1400,
        start: '2026-06-25T07:00:00Z',
        stop: '2026-06-25T08:00:00Z',
        guid: 'g1',
        comments: 'old');
    final svc = await RedmineService.create(
        httpClient: backend(timeEntries: [done], puts: puts));
    addTearDown(svc.dispose);
    final list = svc.timeEntries.firstWhere((l) => l.any((e) => !e.isHeader));
    svc.setBaseUrl('https://x');
    svc.login('', 'key');
    final rows = await list.timeout(const Duration(seconds: 5));
    final row = rows.firstWhere((e) => !e.isHeader);
    final ok = await svc.updateEntry(
        guid: row.guid, description: 'new desc', activityId: 6);
    expect(ok, isTrue);
    expect(puts, hasLength(1));
    expect(puts.first['comments'], 'new desc');
    expect(puts.first['activity_id'], 6);
    expect(puts.first.containsKey('hours'), isTrue);
    expect(puts.first.containsKey('spent_on'), isTrue);
  });

  test('stop before start POST confirms → one entry, no duplicate', () async {
    final posts = <Map<String, dynamic>>[];
    final puts = <Map<String, dynamic>>[];
    final done = entry(
        id: 1500,
        start: '2026-06-25T07:00:00Z',
        stop: '2026-06-25T08:00:00Z',
        guid: 'gx',
        comments: 'past');
    final svc = await RedmineService.create(
        httpClient: backend(
            timeEntries: [done], posts: posts, puts: puts, postDelayMs: 120));
    addTearDown(svc.dispose);
    final firstList =
        svc.timeEntries.firstWhere((l) => l.any((e) => !e.isHeader));
    svc.setBaseUrl('https://x');
    svc.login('', 'key');
    final list = await firstList.timeout(const Duration(seconds: 5));
    final row = list.firstWhere((e) => !e.isHeader);

    svc.continueEntry(row.guid); // POST (delayed 120ms) goes in flight
    svc.stop(); // stop before the POST confirms
    await Future<void>.delayed(const Duration(milliseconds: 450));

    expect(posts, hasLength(1), reason: 'only the open POST — no duplicate');
    expect(puts, hasLength(1), reason: 'stop PUTs the open entry');
  });

  test('add idle as new entry: stops current + posts idle on picked issue',
      () async {
    final posts = <Map<String, dynamic>>[];
    final puts = <Map<String, dynamic>>[];
    final open = entry(
        id: 1500,
        start: '2026-06-25T07:00:00Z',
        stop: '',
        guid: 'run',
        comments: 'work');
    final svc = await RedmineService.create(
        httpClient: backend(timeEntries: [open], posts: posts, puts: puts));
    addTearDown(svc.dispose);
    final running = svc.timerState.firstWhere((t) => t != null && t.isRunning);
    svc.setBaseUrl('https://x');
    svc.login('', 'key');
    await running.timeout(const Duration(seconds: 5)); // discovered running

    final idleStart = DateTime.now().subtract(const Duration(minutes: 10));
    svc.logIdleAsNewEntry(idleStart,
        issueId: 23409, projectId: 75, subject: 'Meeting', projectName: 'SUMA');
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // the running entry was stopped (PUT sets toggl_stop)
    expect(puts, isNotEmpty);
    final putCfs = (puts.first['custom_fields'] as List).cast<Map>();
    expect(
        putCfs.any((c) => c['id'] == 14 && (c['value'] as String).isNotEmpty),
        isTrue);
    // a new completed entry was POSTed against the picked issue
    expect(posts, hasLength(1));
    expect(posts.first['issue_id'], 23409);
    final postCfs = (posts.first['custom_fields'] as List).cast<Map>();
    String cf(int id) =>
        postCfs.firstWhere((c) => c['id'] == id)['value'] as String;
    expect(cf(12), isNotEmpty); // toggl_start = idle start
    expect(cf(14), isNotEmpty); // toggl_stop = now (a completed entry)
  });

  test('deleteEntry DELETEs by id', () async {
    final deletes = <int>[];
    final done = entry(
        id: 1401,
        start: '2026-06-25T07:00:00Z',
        stop: '2026-06-25T08:00:00Z',
        guid: 'g2');
    final svc = await RedmineService.create(
        httpClient: backend(timeEntries: [done], deletes: deletes));
    addTearDown(svc.dispose);
    final list = svc.timeEntries.firstWhere((l) => l.any((e) => !e.isHeader));
    svc.setBaseUrl('https://x');
    svc.login('', 'key');
    final rows = await list.timeout(const Duration(seconds: 5));
    final row = rows.firstWhere((e) => !e.isHeader);
    expect(svc.deleteEntry(row.guid), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    expect(deletes, contains(1401));
  });
}

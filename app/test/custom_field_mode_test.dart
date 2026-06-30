@TestOn('vm')
library;

// "Simple mode" (custom fields off) + the user-configurable field ids:
//  - settings persist and reload
//  - createTimeEntry omits custom_fields when the ids are 0
//  - simple mode defers the running timer (no POST on start; one plain POST on
//    stop, with no custom_fields)
//  - a 422 while custom fields are sent auto-retries without them, saves the
//    entry, disables sending (sticky), and emits the alert
//  - a user-entered id survives login name-resolution

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:redtick/src/data/redmine_api_client.dart';
import 'package:redtick/src/data/redmine_service.dart';
import 'package:redtick/src/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A minimal stateful backend. POSTs append to [store]; with [reject422WithCf]
/// any write carrying a non-empty `custom_fields` array is rejected (mimics an
/// instance that doesn't have the toggl_* fields).
http.Client cfBackend({
  required List<Map<String, dynamic>> store,
  List<Map<String, dynamic>>? posts,
  List<Map<String, dynamic>>? puts,
  bool reject422WithCf = false,
  bool dropCf = false, // accept the write (201) but silently drop custom fields
}) {
  var nextId = 4000;
  http.Response j(Object o, [int s = 200]) => http.Response(jsonEncode(o), s,
      headers: {'content-type': 'application/json'});
  bool hasCf(Map body) =>
      body['custom_fields'] is List && (body['custom_fields'] as List).isNotEmpty;

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
              'subject': 'Demo',
              'project': {'id': 75, 'name': 'SUMA'},
              'status': {'name': 'Open', 'is_closed': false},
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
        for (final e in store) {
          if (e['id'] == int.parse(m.group(1)!)) return j({'time_entry': e});
        }
        return http.Response('not found', 404);
      }
      if (p.endsWith('/time_entries.json')) {
        return j({'time_entries': store, 'total_count': store.length});
      }
    }
    if (req.method == 'POST' && p.endsWith('/time_entries.json')) {
      final body =
          (jsonDecode(req.body) as Map)['time_entry'] as Map<String, dynamic>;
      posts?.add(body);
      if (reject422WithCf && hasCf(body)) {
        return j({
          'errors': ['toggl_start is invalid']
        }, 422);
      }
      final id = nextId++;
      store.add({
        'id': id,
        'project': {'id': body['project_id'] ?? 75},
        'issue': {'id': body['issue_id'] ?? 23409},
        'activity': {'id': body['activity_id'] ?? 6},
        'comments': body['comments'] ?? '',
        'hours': body['hours'] ?? 0,
        'spent_on': '2026-06-25',
        'custom_fields': dropCf ? const [] : (body['custom_fields'] ?? const []),
      });
      return j({
        'time_entry': {'id': id}
      }, 201);
    }
    if (req.method == 'PUT') {
      final body =
          (jsonDecode(req.body) as Map)['time_entry'] as Map<String, dynamic>;
      puts?.add(body);
      if (reject422WithCf && hasCf(body)) {
        return j({
          'errors': ['toggl_stop is invalid']
        }, 422);
      }
      return http.Response('', 204);
    }
    if (req.method == 'DELETE') {
      final m = RegExp(r'/time_entries/(\d+)\.json').firstMatch(p);
      if (m != null) {
        store.removeWhere((e) => e['id'] == int.parse(m.group(1)!));
      }
      return http.Response('', 204);
    }
    return http.Response('not found', 404);
  });
}

Future<RedmineService> _loggedIn(http.Client client) async {
  final svc = await RedmineService.create(httpClient: client);
  final ready = svc.loginState.firstWhere((e) => e.loggedIn);
  svc.setBaseUrl('https://x');
  svc.login('', 'key');
  await ready.timeout(const Duration(seconds: 5));
  return svc;
}

void main() {
  test('settings persist and reload', () async {
    SharedPreferences.setMockInitialValues({});
    final s1 = await RedmineService.create();
    addTearDown(s1.dispose);
    await s1.setSendCustomFields(false);
    await s1.setCustomFieldIds(start: 21, stop: 23, guid: 22);
    expect(s1.sendCustomFields, isFalse);
    expect(s1.cfStartId, 21);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('cf_send'), isFalse);
    expect(prefs.getInt('cf_id_start'), 21);
    expect(prefs.getBool('cf_user_set'), isTrue);

    final s2 = await RedmineService.create();
    addTearDown(s2.dispose);
    expect(s2.sendCustomFields, isFalse);
    expect([s2.cfStartId, s2.cfStopId, s2.cfGuidId], [21, 23, 22]);
  });

  test('createTimeEntry omits custom_fields when the ids are 0', () async {
    final posts = <Map<String, dynamic>>[];
    final client = MockClient((req) async {
      posts.add(
          (jsonDecode(req.body) as Map)['time_entry'] as Map<String, dynamic>);
      return http.Response(
          jsonEncode({
            'time_entry': {'id': 1}
          }),
          201,
          headers: {'content-type': 'application/json'});
    });
    final api = RedmineApiClient(baseUrl: 'https://x', apiKey: 'k', client: client);

    await api.createTimeEntry(
      issueId: 1, projectId: 0, hours: 1, spentOn: DateTime(2026, 6, 25),
      comments: 'c', activityId: 6, togglStart: 'a', togglStop: 'b',
      togglGuid: 'g', cfStart: 0, cfStop: 0, cfGuid: 0,
    );
    expect(posts.single.containsKey('custom_fields'), isFalse);

    await api.createTimeEntry(
      issueId: 1, projectId: 0, hours: 1, spentOn: DateTime(2026, 6, 25),
      comments: 'c', activityId: 6, togglStart: 'a', togglStop: 'b',
      togglGuid: 'g', cfStart: 12, cfStop: 14, cfGuid: 13,
    );
    expect(posts.last['custom_fields'], hasLength(3));
  });

  test('simple mode defers the timer: no POST on start, one plain POST on stop',
      () async {
    SharedPreferences.setMockInitialValues({'cf_send': false});
    final store = <Map<String, dynamic>>[];
    final posts = <Map<String, dynamic>>[];
    final svc = await _loggedIn(cfBackend(store: store, posts: posts));
    addTearDown(svc.dispose);
    expect(svc.sendCustomFields, isFalse);

    svc.startEntryForIssue(issueId: 23409, projectId: 75, description: 'A');
    final running = await svc.runningEntries
        .firstWhere((l) => l.where((e) => e.isRunning).length == 1)
        .timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(posts, isEmpty, reason: 'deferred — no POST while running');

    final guid = running.firstWhere((e) => e.isRunning).guid;
    svc.stopEntry(guid);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(posts, hasLength(1), reason: 'stop creates one completed entry');
    expect(posts.single.containsKey('custom_fields'), isFalse);
    expect(posts.single['hours'], isNotNull);
  });

  test('a custom-field rejection auto-retries without them, then disables+alerts',
      () async {
    SharedPreferences.setMockInitialValues({}); // sending on by default
    final store = <Map<String, dynamic>>[];
    final posts = <Map<String, dynamic>>[];
    final svc = await _loggedIn(
        cfBackend(store: store, posts: posts, reject422WithCf: true));
    addTearDown(svc.dispose);
    expect(svc.sendCustomFields, isTrue);

    final disabled = svc.customFieldsAutoDisabled.first;
    svc.startEntryForIssue(issueId: 23409, projectId: 75, description: 'A');
    final running = await svc.runningEntries
        .firstWhere((l) => l.where((e) => e.isRunning).length == 1)
        .timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    svc.stopEntry(running.firstWhere((e) => e.isRunning).guid);

    await disabled.timeout(const Duration(seconds: 5)); // alert fired
    expect(svc.sendCustomFields, isFalse, reason: 'auto-disabled (sticky)');
    expect(store, hasLength(1), reason: 'the entry was saved on retry');
    expect(posts.any((b) => !b.containsKey('custom_fields')), isTrue,
        reason: 'the successful write carried no custom fields');
  });

  test('silently-dropped custom fields (201, not 422) are detected: disable+alert',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = <Map<String, dynamic>>[];
    // The instance accepts the write but stores no custom fields (Redmine
    // ignores ids the user can't set) — there is NO 422 to catch.
    final svc = await _loggedIn(cfBackend(store: store, dropCf: true));
    addTearDown(svc.dispose);
    expect(svc.sendCustomFields, isTrue);

    final disabled = svc.customFieldsAutoDisabled.first;
    svc.startEntryForIssue(issueId: 23409, projectId: 75, description: 'A');
    await disabled.timeout(const Duration(seconds: 5)); // alert must fire
    expect(svc.sendCustomFields, isFalse, reason: 'round-trip check disabled it');
  });

  test('simple-mode editor edits duration via the standard hours field',
      () async {
    SharedPreferences.setMockInitialValues({'cf_send': false});
    final store = <Map<String, dynamic>>[
      {
        'id': 5001,
        'project': {'id': 75},
        'issue': {'id': 23409},
        'activity': {'id': 6},
        'comments': 'x',
        'hours': 1.0,
        'spent_on': '2026-06-25',
        'custom_fields': [
          {'id': 12, 'name': 'toggl_start', 'value': '2026-06-25T09:00:00Z'},
          {'id': 14, 'name': 'toggl_stop', 'value': '2026-06-25T10:00:00Z'},
          {'id': 13, 'name': 'toggl_guid', 'value': 'g1'},
        ],
      }
    ];
    final puts = <Map<String, dynamic>>[];
    final svc = await _loggedIn(cfBackend(store: store, puts: puts));
    addTearDown(svc.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 150)); // let refresh land

    final guid =
        svc.currentTimeEntries!.firstWhere((e) => !e.isHeader).guid;
    final ok = await svc.updateEntryFields(guid: guid, hours: 2.5);
    expect(ok, isTrue);
    expect(puts.last['hours'], 2.5);
    expect(puts.last.containsKey('custom_fields'), isFalse,
        reason: 'duration needs no custom fields');
  });

  test('turning custom fields on probes immediately and disables if unsupported',
      () async {
    SharedPreferences.setMockInitialValues({'cf_send': false});
    final store = <Map<String, dynamic>>[];
    // dropCf: the throwaway probe entry posts (201) but its custom fields are
    // silently dropped — the round-trip check must catch it at toggle time.
    final svc = await _loggedIn(cfBackend(store: store, dropCf: true));
    addTearDown(svc.dispose);
    await Future<void>.delayed(
        const Duration(milliseconds: 150)); // let refresh load issues/projects

    final disabled = svc.customFieldsAutoDisabled.first;
    await svc.setSendCustomFields(true);
    await svc.verifyCustomFieldsNow();

    await disabled.timeout(const Duration(seconds: 5)); // told right away
    expect(svc.sendCustomFields, isFalse);
    expect(store, isEmpty, reason: 'the probe entry was deleted');
  });

  test('editing an entry after re-enabling detects dropped custom fields',
      () async {
    SharedPreferences.setMockInitialValues({'cf_send': false});
    final store = <Map<String, dynamic>>[
      {
        'id': 6001,
        'project': {'id': 75},
        'issue': {'id': 23409},
        'activity': {'id': 6},
        'comments': 'x',
        'hours': 1.0,
        'spent_on': '2026-06-25',
        'custom_fields': const [],
      }
    ];
    final svc = await _loggedIn(cfBackend(store: store, dropCf: true));
    addTearDown(svc.dispose);
    await Future<void>.delayed(const Duration(milliseconds: 150));

    // Re-enable WITHOUT probing (set the field directly is internal), then edit.
    final disabled = svc.customFieldsAutoDisabled.first;
    await svc.setSendCustomFields(true);
    final guid = svc.currentTimeEntries!.firstWhere((e) => !e.isHeader).guid;
    await svc.updateEntry(guid: guid, description: 'edited');

    await disabled.timeout(const Duration(seconds: 5));
    expect(svc.sendCustomFields, isFalse);
  });

  test('the "custom fields off" alert fires on every disable, not just once',
      () async {
    SharedPreferences.setMockInitialValues({'cf_send': false});
    final svc = await _loggedIn(cfBackend(store: [], dropCf: true));
    addTearDown(svc.dispose);
    await Future<void>.delayed(
        const Duration(milliseconds: 150)); // load issues for the probe

    final container = ProviderContainer(
        overrides: [coreServiceProvider.overrideWithValue(svc)]);
    addTearDown(container.dispose);
    final fired = <Object?>[];
    container.listen(customFieldsAutoDisabledProvider, (_, next) {
      final n = next.asData?.value;
      if (n != null) fired.add(n);
    });

    // Toggle on → probe drops the fields → disable + notice. Do it twice.
    await svc.setSendCustomFields(true);
    await svc.verifyCustomFieldsNow();
    await Future<void>.delayed(const Duration(milliseconds: 30));
    await svc.setSendCustomFields(true);
    await svc.verifyCustomFieldsNow();
    await Future<void>.delayed(const Duration(milliseconds: 30));

    expect(fired.length, 2,
        reason: 'each disable must alert — identical messages must not dedup');
  });

  test('a user-entered id survives login name-resolution', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = await RedmineService.create(httpClient: cfBackend(store: []));
    addTearDown(svc.dispose);
    await svc.setCustomFieldIds(start: 91, stop: 93, guid: 92);

    final ready = svc.loginState.firstWhere((e) => e.loggedIn);
    svc.setBaseUrl('https://x');
    svc.login('', 'key');
    await ready.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect([svc.cfStartId, svc.cfStopId, svc.cfGuidId], [91, 93, 92]);
  });
}

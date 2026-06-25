@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:redtick/src/data/offline_queue.dart';
import 'package:redtick/src/data/redmine_api_client.dart';

void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('redtick_q');
    file = File('${tmp.path}/pending.json');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  RedmineApiClient apiRecording(List<String> calls) {
    final client = MockClient((req) async {
      switch (req.method) {
        case 'POST':
          calls.add('create');
          return http.Response(
              jsonEncode({
                'time_entry': {'id': 99}
              }),
              201,
              headers: {'content-type': 'application/json'});
        case 'PUT':
          calls.add('update');
          return http.Response('', 204);
        case 'DELETE':
          calls.add('delete');
          return http.Response('', 204);
      }
      return http.Response('', 404);
    });
    return RedmineApiClient(baseUrl: 'https://x', apiKey: 'k', client: client);
  }

  test('persists across restart and replays ops in order', () async {
    final calls = <String>[];
    final q1 = OfflineQueue(() async => file);
    await q1.enqueue({
      'kind': 'update',
      'id': 5,
      'hours': 1.0,
      'togglStop': '2026-06-25T08:00:00Z',
      'cfStop': 14,
    });
    await q1.enqueue({'kind': 'delete', 'id': 6});
    expect(q1.length, 2);
    expect(file.existsSync(), isTrue);

    // Simulate an app restart: a fresh queue loads from the same file.
    final q2 = OfflineQueue(() async => file);
    final flushed = await q2.replay(apiRecording(calls));
    expect(flushed, 2);
    expect(q2.length, 0);
    expect(calls, ['update', 'delete']);
  });

  test('stops at a network failure and keeps ops for next reconnect', () async {
    var offline = true;
    final client = MockClient((req) async {
      if (offline) throw const SocketException('offline');
      return http.Response('', 204);
    });
    final api = RedmineApiClient(baseUrl: 'https://x', apiKey: 'k', client: client);

    final q = OfflineQueue(() async => file);
    await q.enqueue({'kind': 'delete', 'id': 1});
    await q.enqueue({'kind': 'delete', 'id': 2});

    expect(await q.replay(api), 0); // still offline
    expect(q.length, 2); // nothing lost

    offline = false;
    expect(await q.replay(api), 2); // reconnected → flush
    expect(q.length, 0);
  });

  test('drops an op that fails permanently (e.g. 404)', () async {
    final client = MockClient((req) async => http.Response('gone', 404));
    final api = RedmineApiClient(baseUrl: 'https://x', apiKey: 'k', client: client);
    final q = OfflineQueue(() async => file);
    await q.enqueue({'kind': 'delete', 'id': 7});
    expect(await q.replay(api), 0); // not flushed (it errored)…
    expect(q.length, 0); // …but dropped so it won't retry forever
  });
}

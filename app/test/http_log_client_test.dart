@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:redtick/src/data/http_log.dart';
import 'package:redtick/src/data/redmine_api_client.dart';

void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('redtick_log_client');
    file = File('${tmp.path}/redtick_http.log');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  MockClient userClient() => MockClient((req) async => http.Response(
        jsonEncode({
          'user': {'id': 1, 'firstname': 'A', 'lastname': 'B'}
        }),
        200,
        headers: {'content-type': 'application/json'},
      ));

  test('client records the request/response through the logger', () async {
    final lg = HttpLogger(enabled: true, fileOverride: () async => file);
    final api = RedmineApiClient(
        baseUrl: 'https://x', apiKey: 'TOPSECRET', client: userClient(),
        logger: lg);

    await api.currentUser();
    await lg.flush();

    final txt = file.readAsStringSync();
    expect(txt, contains('GET https://x/users/current.json'));
    expect(txt, contains('«redacted»'));
    expect(txt, isNot(contains('TOPSECRET')));
    expect(txt, contains('"id":1'));
  });

  test('disabled logger leaves no file', () async {
    final lg = HttpLogger(enabled: false, fileOverride: () async => file);
    final api = RedmineApiClient(
        baseUrl: 'https://x', apiKey: 'k', client: userClient(), logger: lg);

    await api.currentUser();
    await lg.flush();
    expect(file.existsSync(), isFalse);
  });

  test('logs the error body for a failing GET and enriches the message',
      () async {
    final client = MockClient((req) async =>
        http.Response('{"errors":["nope"]}', 500,
            headers: {'content-type': 'application/json'}));
    final lg = HttpLogger(enabled: true, fileOverride: () async => file);
    final api = RedmineApiClient(
        baseUrl: 'https://x', apiKey: 'k', client: client, logger: lg);

    await expectLater(
      api.projects(),
      throwsA(isA<RedmineException>()
          .having((e) => e.message, 'message', contains('nope'))),
    );
    await lg.flush();
    expect(file.readAsStringSync(), contains('{"errors":["nope"]}'));
  });
}

@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/data/http_log.dart';

void main() {
  late Directory tmp;
  late File file;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('redtick_log');
    file = File('${tmp.path}/redtick_http.log');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('disabled is a no-op (no file written)', () async {
    final lg = HttpLogger(enabled: false, fileOverride: () async => file);
    lg.record(
      method: 'GET',
      url: 'https://x/a.json',
      requestHeaders: const {'X-Redmine-API-Key': 'k'},
      statusCode: 200,
      responseBody: 'ok',
      elapsed: Duration.zero,
    );
    await lg.flush();
    expect(file.existsSync(), isFalse);
  });

  test('enabled writes a readable record and redacts the API key', () async {
    final lg = HttpLogger(enabled: true, fileOverride: () async => file);
    lg.record(
      method: 'GET',
      url: 'https://x/users/current.json',
      requestHeaders: const {
        'X-Redmine-API-Key': 'TOPSECRET123',
        'Accept': 'application/json',
      },
      statusCode: 200,
      responseHeaders: const {'content-type': 'application/json'},
      responseBody: '{"user":{"id":1}}',
      elapsed: const Duration(milliseconds: 12),
    );
    await lg.flush();

    final txt = file.readAsStringSync();
    expect(txt, contains('GET https://x/users/current.json'));
    expect(txt, contains('«redacted»'));
    expect(txt, isNot(contains('TOPSECRET123')));
    expect(txt, contains('200'));
    expect(txt, contains('"user":{"id":1}'));
  });

  test('logs the request body for writes', () async {
    final lg = HttpLogger(enabled: true, fileOverride: () async => file);
    lg.record(
      method: 'POST',
      url: 'https://x/time_entries.json',
      requestHeaders: const {'Content-Type': 'application/json'},
      requestBody: '{"time_entry":{"hours":1.0}}',
      statusCode: 201,
      elapsed: Duration.zero,
    );
    await lg.flush();
    expect(file.readAsStringSync(), contains('{"time_entry":{"hours":1.0}}'));
  });

  test('records the exception path', () async {
    final lg = HttpLogger(enabled: true, fileOverride: () async => file);
    lg.record(
      method: 'GET',
      url: 'https://x/a.json',
      requestHeaders: const {},
      elapsed: const Duration(milliseconds: 5),
      error: const SocketException('offline'),
    );
    await lg.flush();
    final txt = file.readAsStringSync();
    expect(txt, contains('ERROR'));
    expect(txt, contains('offline'));
  });

  test('rotates to .1 once the size cap is exceeded', () async {
    // Pre-fill past the ~5 MB cap, then one more record triggers rotation.
    file.writeAsStringSync('x' * (5 * 1024 * 1024 + 16));
    final lg = HttpLogger(enabled: true, fileOverride: () async => file);
    lg.record(
      method: 'GET',
      url: 'https://x/fresh.json',
      requestHeaders: const {},
      statusCode: 200,
      elapsed: Duration.zero,
    );
    await lg.flush();

    final backup = File('${file.path}.1');
    expect(backup.existsSync(), isTrue); // old content moved aside
    final fresh = file.readAsStringSync();
    expect(fresh, contains('fresh.json'));
    expect(fresh.length, lessThan(4096)); // only the new record
  });

  test('clear() removes the file and its backup', () async {
    final lg = HttpLogger(enabled: true, fileOverride: () async => file);
    lg.record(
      method: 'GET',
      url: 'https://x/a.json',
      requestHeaders: const {},
      statusCode: 200,
      elapsed: Duration.zero,
    );
    await lg.flush();
    File('${file.path}.1').writeAsStringSync('old');
    expect(file.existsSync(), isTrue);

    await lg.clear();
    expect(file.existsSync(), isFalse);
    expect(File('${file.path}.1').existsSync(), isFalse);
  });
}

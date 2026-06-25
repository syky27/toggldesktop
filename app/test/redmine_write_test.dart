@TestOn('vm')
library;

// Live write-cycle probe (Slice 1): create a RUNNING entry (toggl_stop empty),
// read it back, stop it (PUT hours + toggl_stop), then DELETE it — so nothing is
// left on the real Redmine. Skipped unless a key is provided:
//
//   REDTICK_TEST_KEY=<key> flutter test test/redmine_write_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/data/redmine_api_client.dart';

const cfStart = 12, cfStop = 14, cfGuid = 13; // resolved ids for this instance

String isoZ(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}-${two(u.month)}-${two(u.day)}'
      'T${two(u.hour)}:${two(u.minute)}:${two(u.second)}Z';
}

void main() {
  final key = Platform.environment['REDTICK_TEST_KEY'];
  final host = Platform.environment['REDTICK_TEST_HOST'] ??
      'https://servicedesk.sumanet.cz';

  test('create running -> stop -> delete', () async {
    if (key == null || key.isEmpty) {
      markTestSkipped('REDTICK_TEST_KEY not set');
      return;
    }
    final api = RedmineApiClient(baseUrl: host, apiKey: key);
    int? createdId;
    addTearDown(() async {
      if (createdId != null) {
        try {
          await api.deleteTimeEntry(createdId);
          // ignore: avoid_print
          print('cleanup: deleted $createdId');
        } catch (_) {}
      }
      api.dispose();
    });

    final issues = await api.myOpenIssues();
    expect(issues, isNotEmpty);
    final issueId = (issues.first['id'] as num).toInt();

    final start = DateTime.now();
    final guid = 'redtick-test-${start.millisecondsSinceEpoch}';

    // 1. create a RUNNING entry (toggl_stop empty, hours 0).
    createdId = await api.createTimeEntry(
      issueId: issueId,
      projectId: 0,
      hours: 0,
      spentOn: start,
      comments: 'redtick-test (auto, deleted by test)',
      activityId: 6,
      togglStart: isoZ(start),
      togglStop: '',
      togglGuid: guid,
      cfStart: cfStart,
      cfStop: cfStop,
      cfGuid: cfGuid,
    );
    // ignore: avoid_print
    print('created running entry id=$createdId on issue #$issueId guid=$guid');
    expect(createdId, greaterThan(0));

    // 2. stop it: finalize hours + set toggl_stop.
    final stop = start.add(const Duration(minutes: 5));
    await api.updateTimeEntry(
      id: createdId,
      hours: 5 / 60.0,
      togglStop: isoZ(stop),
      cfStop: cfStop,
    );
    // ignore: avoid_print
    print('stopped entry id=$createdId (hours=${(5 / 60).toStringAsFixed(3)})');

    // (tearDown deletes it.)
  }, timeout: const Timeout(Duration(seconds: 60)));
}

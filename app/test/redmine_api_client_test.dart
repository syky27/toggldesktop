@TestOn('vm')
library;

// ignore_for_file: avoid_print

// Live data-layer probe for the pure-Dart Redmine client (Slice 0). Hits the
// real backend; skipped unless a key is provided:
//
//   REDTICK_TEST_KEY=<key> [REDTICK_TEST_HOST=https://servicedesk.sumanet.cz] \
//     flutter test test/redmine_api_client_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/data/redmine_api_client.dart';

void main() {
  final key = Platform.environment['REDTICK_TEST_KEY'];
  final host = Platform.environment['REDTICK_TEST_HOST'] ??
      'https://servicedesk.sumanet.cz';

  test('account load against the real Redmine', () async {
    if (key == null || key.isEmpty) {
      markTestSkipped('REDTICK_TEST_KEY not set');
      return;
    }
    final api = RedmineApiClient(baseUrl: host, apiKey: key);
    try {
      final user = await api.currentUser();
      print('user id=${user['id']} mail=${user['mail']} '
          'name=${user['firstname']} ${user['lastname']}');

      final projects = await api.projects();
      final issues = await api.myOpenIssues();
      final tes = await api.recentTimeEntries();
      final acts = await api.activities();
      print('projects=${projects.length} myOpenIssues=${issues.length} '
          'recentTimeEntries=${tes.length} activities=${acts.length}');

      // Show how the running-entry detection sees the data.
      var open = 0;
      for (final t in tes) {
        final cfs = (t['custom_fields'] as List?) ?? const [];
        String? stop;
        for (final f in cfs) {
          if (f is Map && f['name'] == 'toggl_stop') stop = f['value'] as String?;
        }
        if (stop == null || stop.isEmpty) open++;
      }
      print('open (toggl_stop empty / "running") entries in window: $open');

      expect(user['id'], isNotNull);
      expect(projects, isNotEmpty);
    } finally {
      api.dispose();
    }
  }, timeout: const Timeout(Duration(seconds: 60)));
}

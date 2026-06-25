@TestOn('vm')
library;

// ignore_for_file: avoid_print

// Full pure-Dart service flow (Slice 0): login -> account load -> entry list +
// running detection, against the real backend. Mocks shared_preferences so no
// platform channel is needed. Skipped unless a key is provided:
//
//   REDTICK_TEST_KEY=<key> flutter test test/redmine_service_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/data/redmine_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final key = Platform.environment['REDTICK_TEST_KEY'];
  final host = Platform.environment['REDTICK_TEST_HOST'] ??
      'https://servicedesk.sumanet.cz';

  test('login + account load + list', () async {
    if (key == null || key.isEmpty) {
      markTestSkipped('REDTICK_TEST_KEY not set');
      return;
    }
    SharedPreferences.setMockInitialValues({});
    final svc = await RedmineService.create();
    addTearDown(svc.dispose);

    final loginEv = svc.loginState.firstWhere((e) => e.loggedIn);
    final firstList = svc.timeEntries.first;
    final firstTimer = svc.timerState.first;

    svc.setBaseUrl(host);
    final started = svc.login('', key);
    expect(started, isTrue);

    final ev = await loginEv.timeout(const Duration(seconds: 30));
    expect(ev.loggedIn, isTrue);
    expect(ev.userId, greaterThan(0));

    final list = await firstList.timeout(const Duration(seconds: 30));
    final timer = await firstTimer.timeout(const Duration(seconds: 30));

    final headers = list.where((e) => e.isHeader).length;
    final rows = list.where((e) => !e.isHeader).length;
    print('login uid=${ev.userId} | list rows=$rows headers=$headers '
        'activities=${svc.availableActivities.length} '
        'running=${timer == null ? "none" : timer.projectLabel}');
    if (list.isNotEmpty) {
      final sample = list.firstWhere((e) => !e.isHeader);
      print('sample row: project="${sample.projectLabel}" '
          'desc="${sample.description}" dur=${sample.duration} '
          'time=${sample.startTimeString}-${sample.endTimeString}');
    }
    final dayHeader = list.where((e) => e.isHeader).firstOrNull;
    if (dayHeader != null) {
      print('day header: "${dayHeader.dateHeader}" total=${dayHeader.dateDuration}');
    }

    expect(rows, greaterThan(0));
    expect(headers, greaterThan(0));
    expect(svc.availableActivities, isNotEmpty);
  }, timeout: const Timeout(Duration(seconds: 90)));
}

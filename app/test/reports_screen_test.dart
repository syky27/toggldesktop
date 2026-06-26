import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/models/time_entry.dart';
import 'package:redtick/src/state/providers.dart';
import 'package:redtick/src/ui/screens/reports_screen.dart';
import 'package:redtick/src/ui/theme.dart';

/// Noon today — always inside this week, this month and the last 30 days,
/// whatever date the suite runs on (keeps the widget test date-stable).
DateTime get _noonToday {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, 12);
}

TimeEntry _entry({
  required int durationInSeconds,
  required String projectLabel,
  String color = '#3b82f6',
}) {
  final at = _noonToday;
  return TimeEntry(
    id: 1,
    guid: 'g',
    description: '',
    durationInSeconds: durationInSeconds,
    duration: '',
    projectLabel: projectLabel,
    taskLabel: '',
    clientLabel: '',
    color: color,
    tags: '',
    billable: false,
    started: at.millisecondsSinceEpoch ~/ 1000,
    ended: at.millisecondsSinceEpoch ~/ 1000 + durationInSeconds,
    startTimeString: '',
    endTimeString: '',
    isHeader: false,
    dateHeader: '',
    dateDuration: '',
    unsynced: false,
    error: '',
    activityId: 0,
  );
}

Widget _host(List<TimeEntry> entries) => ProviderScope(
      overrides: [
        timeEntriesProvider.overrideWith((ref) => Stream.value(entries)),
      ],
      child: MaterialApp(
        theme: RedtickTheme.light(),
        home: const Scaffold(body: ReportsScreen()),
      ),
    );

void main() {
  testWidgets('renders grand total and per-project breakdown', (tester) async {
    await tester.pumpWidget(_host([
      _entry(durationInSeconds: 3600, projectLabel: 'Alpha'),
      _entry(durationInSeconds: 1800, projectLabel: 'Beta', color: '#16a34a'),
    ]));
    await tester.pump(); // let the stream emit

    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    // Grand total 1:30:00, plus per-project 1:00:00 and 0:30:00.
    expect(find.text('1:30:00'), findsOneWidget);
    expect(find.text('1:00:00'), findsOneWidget);
    expect(find.text('0:30:00'), findsOneWidget);
  });

  testWidgets('switching the period segment keeps the page working',
      (tester) async {
    await tester.pumpWidget(_host([
      _entry(durationInSeconds: 3600, projectLabel: 'Alpha'),
    ]));
    await tester.pump();

    await tester.tap(find.text('Month'));
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
    expect(find.text('1:00:00'), findsWidgets);

    await tester.tap(find.text('30 days'));
    await tester.pump();
    expect(find.text('Alpha'), findsOneWidget);
  });

  testWidgets('shows the empty state when nothing is tracked', (tester) async {
    await tester.pumpWidget(_host(const []));
    await tester.pump();

    expect(find.text('No time tracked in this period'), findsOneWidget);
  });
}

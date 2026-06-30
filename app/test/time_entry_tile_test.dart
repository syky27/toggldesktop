import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:redtick/src/models/time_entry.dart';
import 'package:redtick/src/ui/theme.dart';
import 'package:redtick/src/ui/widgets/time_entry_tile.dart';

// A completed entry with a time range + total, and no subline (empty labels →
// no EntrySubline, which is a ConsumerWidget) so the test needs no ProviderScope.
TimeEntry _entry() => const TimeEntry(
      id: 1,
      guid: 'g',
      description: 'Predcasne ukonceni',
      durationInSeconds: 1335,
      duration: '0:22:15',
      projectLabel: '',
      taskLabel: '',
      clientLabel: '',
      color: '#3b82f6',
      tags: '',
      billable: false,
      started: 0,
      ended: 0,
      startTimeString: '17:43',
      endTimeString: '18:05',
      isHeader: false,
      dateHeader: '',
      dateDuration: '',
      unsynced: false,
      error: '',
      activityId: 0,
    );

Future<void> _pump(WidgetTester tester, double width,
    {bool showTimestamps = true}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, 800);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      theme: RedtickTheme.light(),
      home: Scaffold(
        body: TimeEntryTile(
          entry: _entry(),
          onContinue: () {},
          showTimestamps: showTimestamps,
        ),
      ),
    ),
  );
}

void main() {
  // Offline test: use bundled/fallback fonts instead of fetching from Google.
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('narrow view stacks the range above the total', (tester) async {
    await _pump(tester, 360);
    final range = tester.getRect(find.textContaining('17:43'));
    final total = tester.getRect(find.text('0:22:15'));
    expect(range.bottom, lessThanOrEqualTo(total.top + 1),
        reason: 'range should sit above the total on narrow layouts');
  });

  testWidgets('wide view keeps the range beside the total', (tester) async {
    await _pump(tester, 1000);
    final range = tester.getRect(find.textContaining('17:43'));
    final total = tester.getRect(find.text('0:22:15'));
    expect(range.right, lessThanOrEqualTo(total.left + 1),
        reason: 'range should be left of the total on wide layouts');
    expect((range.center.dy - total.center.dy).abs(), lessThan(8),
        reason: 'range and total share a row on wide layouts');
  });

  testWidgets('simple mode hides the start–stop range, keeps the total',
      (tester) async {
    await _pump(tester, 1000, showTimestamps: false);
    expect(find.textContaining('17:43'), findsNothing);
    expect(find.text('0:22:15'), findsOneWidget); // duration still shown
  });
}

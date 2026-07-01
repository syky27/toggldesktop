import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:redtick/src/data/redmine_service.dart';
import 'package:redtick/src/models/time_entry.dart';
import 'package:redtick/src/ui/widgets/running_start_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

// A running-entry display model (negative duration ⇒ isRunning), started
// [minutesAgo] before now.
TimeEntry _running({required String guid, required int minutesAgo}) {
  final startedAt = DateTime.now().subtract(Duration(minutes: minutesAgo));
  final startEpoch = startedAt.millisecondsSinceEpoch ~/ 1000;
  return TimeEntry(
    id: 0,
    guid: guid,
    description: 'work',
    durationInSeconds: -startEpoch,
    duration: '0:0$minutesAgo:00',
    projectLabel: 'SUMA',
    taskLabel: '#23409',
    clientLabel: '',
    color: '#ff0000',
    tags: '',
    billable: false,
    started: startEpoch,
    ended: 0,
    startTimeString: '',
    endTimeString: '',
    isHeader: false,
    dateHeader: '',
    dateDuration: '',
    unsynced: false,
    error: '',
    activityId: 6,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('tapping the running time opens the adjust dialog, prefilled',
      (tester) async {
    late RedmineService svc;
    await tester.runAsync(() async {
      // A bare service is enough — the dialog only touches it on Save, which
      // this test doesn't reach (the Save→PUT path is covered in the service
      // suite). No login, so no timers/network are started.
      svc = await RedmineService.create(
          httpClient: MockClient((_) async => http.Response('{}', 200)));
    });
    addTearDown(svc.dispose);

    final entry = _running(guid: 'g', minutesAgo: 5);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showRunningStartEditor(context, svc, entry),
            child: const Text('open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The modal opened, prefilled with the current elapsed (~5 min).
    expect(find.text('Adjust running timer'), findsOneWidget);
    expect(find.text('0:05'), findsOneWidget);
    expect(find.textContaining('Starts at'), findsOneWidget);

    // Invalid input surfaces an inline error instead of saving.
    await tester.enterText(find.byType(TextField), 'nope');
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pump();
    expect(find.textContaining('valid duration'), findsOneWidget);
    expect(find.text('Adjust running timer'), findsOneWidget); // still open
  });
}

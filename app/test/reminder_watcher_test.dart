import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/data/redmine_service.dart';
import 'package:redtick/src/platform/notifications.dart';
import 'package:redtick/src/state/providers.dart';
import 'package:redtick/src/state/reminder_notice.dart';
import 'package:redtick/src/ui/widgets/reminder_watcher.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A no-op presenter so the watcher doesn't reach the real OS plugin in tests.
class _NoopPresenter implements NotificationPresenter {
  @override
  Future<void> init() async {}
  @override
  Future<bool> show(String title, String body) async => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('does not nag until idle is sustained across two ticks',
      (tester) async {
    var clock = DateTime(2024, 1, 1, 10, 0, 0); // Monday 10:00

    // No persisted session → not logged in → no running timer, so
    // core.currentTimer is null. The watcher reads that snapshot directly (a
    // cold ref.read of timerStateProvider can't see it), so the test drives the
    // running state through the core, not a provider override. create() touches
    // platform channels (prefs/keychain), so build it under runAsync.
    final core = (await tester.runAsync(RedmineService.create))!;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreServiceProvider.overrideWithValue(core),
          notificationPresenterProvider.overrideWithValue(_NoopPresenter()),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: ReminderWatcher(
              clock: () => clock,
              child: const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
    await tester.pump(); // let the first build settle

    final container = ProviderScope.containerOf(
        tester.element(find.byType(ReminderWatcher)));

    // Satisfy the 10-minute throttle, so the ONLY thing gating the first tick is
    // the sustained-idle guard.
    clock = clock.add(const Duration(minutes: 11));

    // First 30s tick → idleTicks = 1 (< threshold): no notice.
    await tester.pump(const Duration(seconds: 30));
    expect(container.read(reminderNoticeProvider).visible, isFalse);

    // Second tick → idleTicks = 2: the banner is shown.
    await tester.pump(const Duration(seconds: 30));
    expect(container.read(reminderNoticeProvider).visible, isTrue);
  });
}

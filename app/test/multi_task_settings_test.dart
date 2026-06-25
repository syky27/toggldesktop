import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/state/multi_task_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Let the notifier's async `_load()` (which awaits SharedPreferences) settle.
Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MultiTaskSettings persistence', () {
    test('defaults to off when prefs empty', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(multiTaskSettingsProvider).allowConcurrent, false);
    });

    test('set persists', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(multiTaskSettingsProvider.notifier).setAllowConcurrent(true);
      expect(c.read(multiTaskSettingsProvider).allowConcurrent, true);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('allow_concurrent_tracking'), true);
    });

    test('loads persisted value into a fresh container', () async {
      SharedPreferences.setMockInitialValues({
        'allow_concurrent_tracking': true,
      });
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(multiTaskSettingsProvider); // trigger build()/_load()
      await _settle();
      expect(c.read(multiTaskSettingsProvider).allowConcurrent, true);
    });
  });
}

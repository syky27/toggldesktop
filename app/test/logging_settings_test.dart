@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/data/http_log.dart';
import 'package:redtick/src/state/logging_settings.dart';
import 'package:redtick/src/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Let the notifier's async `_load()` (which awaits SharedPreferences) settle.
Future<void> _settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late HttpLogger logger;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('redtick_log_settings');
    logger = HttpLogger(
        fileOverride: () async => File('${tmp.path}/redtick_http.log'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  ProviderContainer container() {
    final c = ProviderContainer(
        overrides: [httpLoggerProvider.overrideWithValue(logger)]);
    addTearDown(c.dispose);
    return c;
  }

  test('defaults to off when prefs empty', () async {
    SharedPreferences.setMockInitialValues({});
    final c = container();
    expect(c.read(loggingSettingsProvider).enabled, false);
  });

  test('setEnabled persists and flips the shared logger', () async {
    SharedPreferences.setMockInitialValues({});
    final c = container();
    await c.read(loggingSettingsProvider.notifier).setEnabled(true);

    expect(c.read(loggingSettingsProvider).enabled, true);
    expect(logger.enabled, true);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('http_logging_enabled'), true);
  });

  test('loads a persisted value and arms the logger', () async {
    SharedPreferences.setMockInitialValues({'http_logging_enabled': true});
    final c = container();
    c.read(loggingSettingsProvider); // trigger build()/_load()
    await _settle();
    expect(c.read(loggingSettingsProvider).enabled, true);
    expect(logger.enabled, true);
  });
}

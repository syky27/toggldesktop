import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'src/data/http_log.dart';
import 'src/data/redmine_service.dart';
import 'src/platform/background_reconcile.dart';
import 'src/state/logging_settings.dart';
import 'src/state/providers.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Background reconcile (iOS + Android): when the OS grants a background window,
  // end a stale live surface left by a timer stopped on another device while
  // locked (the foreground poll is suspended in the background). On iOS the
  // surface is a Live Activity; on Android the running-timer ongoing
  // notification. See background_reconcile.dart.
  if (Platform.isIOS || Platform.isAndroid) {
    await Workmanager().initialize(backgroundDispatcher);
    // Idempotent: updates the pending task. iOS frequency is set in
    // AppDelegate.swift; Android honours `frequency` (15 min minimum).
    await Workmanager().registerPeriodicTask(
      kReconcileTaskId,
      kReconcileTaskId,
      frequency: const Duration(minutes: 20),
    );
  }

  // Arm the HTTP logger from the persisted flag BEFORE building the service, so
  // the very first auto-login (and its custom-field resolution) is captured.
  // The same instance is shared with the settings toggle via httpLoggerProvider.
  final prefs = await SharedPreferences.getInstance();
  final logger = HttpLogger(
    enabled: prefs.getBool(LoggingSettingsNotifier.kEnabled) ?? false,
  );

  // Pure-Dart Redmine backend. `create()` restores a persisted session and
  // auto-logs-in if one exists (the instant-relaunch behaviour). No FFI, no
  // native library, no SQLite.
  final service = await RedmineService.create(logger: logger);

  runApp(
    ProviderScope(
      overrides: [
        coreServiceProvider.overrideWithValue(service),
        httpLoggerProvider.overrideWithValue(logger),
      ],
      child: const RedtickApp(),
    ),
  );
}

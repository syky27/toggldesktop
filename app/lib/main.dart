import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'src/data/redmine_service.dart';
import 'src/platform/background_reconcile.dart';
import 'src/state/providers.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // iOS background reconcile: when iOS grants a BGAppRefresh window, end a Live
  // Activity left stale by a timer stopped on another device while locked (the
  // foreground poll is suspended in the background). See background_reconcile.dart.
  if (Platform.isIOS) {
    await Workmanager().initialize(backgroundDispatcher);
    // Idempotent: updates the pending task. Frequency for iOS is set in
    // AppDelegate.swift; this submits the request.
    await Workmanager().registerPeriodicTask(
      kReconcileTaskId,
      kReconcileTaskId,
      frequency: const Duration(minutes: 20),
    );
  }

  // Pure-Dart Redmine backend. `create()` restores a persisted session and
  // auto-logs-in if one exists (the instant-relaunch behaviour). No FFI, no
  // native library, no SQLite.
  final service = await RedmineService.create();

  runApp(
    ProviderScope(
      overrides: [coreServiceProvider.overrideWithValue(service)],
      child: const RedtickApp(),
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/data/redmine_service.dart';
import 'src/state/providers.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

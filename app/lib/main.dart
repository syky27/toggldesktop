import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/native/core_service.dart';
import 'src/state/db_path.dart';
import 'src/state/providers.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolve a writable DB/log path (FP-25), then start the C core (FP-21).
  final paths = await CorePaths.resolve();
  final core = CoreService.start(
    appName: 'Redtick',
    appVersion: '1.0.0',
    dbPath: paths.dbPath,
    logPath: paths.logPath,
  );

  runApp(
    ProviderScope(
      overrides: [coreServiceProvider.overrideWithValue(core)],
      child: const RedtickApp(),
    ),
  );
}

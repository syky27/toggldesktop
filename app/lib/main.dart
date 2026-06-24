import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/native/cacert.dart';
import 'src/native/core_service.dart';
import 'src/state/db_path.dart';
import 'src/state/providers.dart';
import 'src/ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Resolve a writable DB/log path (FP-25) + CA bundle, then start the C core.
  final paths = await CorePaths.resolve();
  final cacertPath = await CaCert.resolve();
  final core = CoreService.start(
    appName: 'Redtick',
    appVersion: '1.0.0',
    dbPath: paths.dbPath,
    logPath: paths.logPath,
    cacertPath: cacertPath,
  );

  runApp(
    ProviderScope(
      overrides: [coreServiceProvider.overrideWithValue(core)],
      child: const RedtickApp(),
    ),
  );
}

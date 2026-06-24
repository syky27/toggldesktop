import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Resolves a writable per-platform path for the core's SQLite database and log
/// file (passed to `toggl_set_db_path` / `toggl_set_log_path`). Implements FP-25.
///
/// Uses the application-support directory on every platform, which is private,
/// persistent and writable on iOS/Android/macOS/Windows/Linux.
class CorePaths {
  const CorePaths({required this.dbPath, required this.logPath});

  final String dbPath;
  final String logPath;

  static Future<CorePaths> resolve() async {
    final dir = await getApplicationSupportDirectory();
    await Directory(dir.path).create(recursive: true);
    return CorePaths(
      dbPath: p.join(dir.path, 'redtick.db'),
      logPath: p.join(dir.path, 'redtick.log'),
    );
  }
}

import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Materializes the bundled Mozilla CA bundle (`assets/cacert.pem`) to a real
/// file on disk and returns its path, for `toggl_set_cacert_path`.
///
/// The core's networking (Poco NetSSL) needs a CA bundle *file path*; bundling
/// our own makes TLS work identically on iOS/Android/macOS/Windows/Linux instead
/// of depending on a system bundle that may be absent (notably on mobile).
class CaCert {
  static Future<String> resolve() async {
    final dir = await getApplicationSupportDirectory();
    final outPath = p.join(dir.path, 'cacert.pem');
    final out = File(outPath);
    if (!await out.exists()) {
      final data = await rootBundle.load('assets/cacert.pem');
      await out.writeAsBytes(data.buffer.asUint8List(), flush: true);
    }
    return outPath;
  }
}

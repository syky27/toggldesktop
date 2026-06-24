@TestOn('vm')
library;

import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/native/core_service.dart';

/// Real end-to-end FFI test of [CoreService] against the built core library.
/// Skipped unless REDTICK_CORE_LIB points at a built
/// libTogglDesktopLibrary.so/.dylib/.dll.
///
/// This is the offline portion of the POC gate (FP-13): it proves the full
/// service — context lifecycle, CA-cert + DB wiring, marshalling, and the
/// complete mandatory-callback registration — links and starts the core
/// (`toggl_ui_start` → `Context::StartEvents` passes `VerifyCallbacks`). It does
/// NOT exercise the network/login round-trip (no Redmine backend in CI).
void main() {
  final libPath = Platform.environment['REDTICK_CORE_LIB'];

  test('CoreService starts the core over FFI (ui_start succeeds)', () {
    final lib = ffi.DynamicLibrary.open(libPath!);
    final tmp = Directory.systemTemp.createTempSync('redtick_ffi_test');

    final core = CoreService.start(
      appName: 'Redtick',
      appVersion: '1.0.0',
      dbPath: '${tmp.path}/test.db',
      cacertPath: '/etc/ssl/certs/ca-certificates.crt',
      logPath: '${tmp.path}/test.log',
      library: lib,
    );

    // If we got here, toggl_context_init + all callback registration +
    // toggl_ui_start all succeeded against the real ABI.
    expect(core, isNotNull);

    // Streams are wired and broadcast.
    expect(core.timeEntries.isBroadcast, isTrue);

    core.dispose();
    tmp.deleteSync(recursive: true);
  }, skip: libPath == null ? 'set REDTICK_CORE_LIB to run' : false);
}

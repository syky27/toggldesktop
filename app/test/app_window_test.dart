import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:redtick/src/platform/window.dart';

/// Contract for the `redtick/window` channel wrapper. The idle integration calls
/// `AppWindow.foreground()` fire-and-forget, so the load-bearing guarantees are:
/// it invokes `foreground`, and it never throws — whatever the native side does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('redtick/window');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('foreground() invokes "foreground" and returns normally', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true; // native returns whether the raise succeeded
    });

    await AppWindow.foreground();

    expect(calls, hasLength(1));
    expect(calls.single.method, 'foreground');
  });

  test('foreground() swallows a PlatformException (best-effort, no throw)',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      throw PlatformException(code: 'denied', message: 'focus theft blocked');
    });

    // The OS refusing the raise must never surface to the caller; the modal
    // prompt shows regardless. This is the fire-and-forget contract the idle
    // integration relies on.
    await expectLater(AppWindow.foreground(), completes);
  });

  test('foreground() tolerates a MissingPluginException (no handler)', () async {
    // No handler registered → MissingPluginException, the most likely real
    // failure on an unconfigured runner. Must still complete quietly.
    await expectLater(AppWindow.foreground(), completes);
  });
}

import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    // Idle detection (design §3.9): report seconds since the last user input so
    // Dart can prompt to keep/discard idle time while a timer runs.
    let idleChannel = FlutterMethodChannel(
      name: "redtick/idle",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    idleChannel.setMethodCallHandler { call, result in
      if call.method == "idleSeconds" {
        guard let anyEvent = CGEventType(rawValue: ~0) else {
          // Should never happen (~0 == kCGAnyInputEventType), but if it did the
          // prompt could never fire — so make it loud instead of a silent 0.
          NSLog("[redtick.idle] native guard FAILED -> returning 0.0")
          result(0.0)
          return
        }
        let seconds = CGEventSource.secondsSinceLastEventType(
          .combinedSessionState, eventType: anyEvent)
        NSLog("[redtick.idle] native idleSeconds = %f", seconds)
        result(seconds)
      } else {
        NSLog("[redtick.idle] native unimplemented method: %@", call.method)
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}

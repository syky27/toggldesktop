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
          result(0.0)
          return
        }
        let seconds = CGEventSource.secondsSinceLastEventType(
          .combinedSessionState, eventType: anyEvent)
        result(seconds)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}

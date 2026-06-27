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

    // Window control (idle bring-to-front): raise our own window so the user
    // sees the "You've been idle" prompt when they return. Mirrors redtick/idle:
    // a single stateless method kept alive by the messenger. `self` is the
    // NSWindow (this class subclasses NSWindow).
    let windowChannel = FlutterMethodChannel(
      name: "redtick/window",
      binaryMessenger: flutterViewController.engine.binaryMessenger)
    windowChannel.setMethodCallHandler { [weak self] call, result in
      if call.method == "foreground" {
        guard let self = self else {
          result(false)
          return
        }
        // Realistic idle case: the app is in the background and possibly
        // minimized while the user is away.
        if self.isMiniaturized {
          self.deminiaturize(nil)
        }
        // Steal focus across apps. activate(ignoringOtherApps:) is deprecated in
        // macOS 14; the zero-arg activate() replaces it. Guard because the
        // deployment target is 10.15.
        if #available(macOS 14.0, *) {
          NSApp.activate()
        } else {
          NSApp.activate(ignoringOtherApps: true)
        }
        self.makeKeyAndOrderFront(nil)
        NSLog("[redtick.window] native foreground -> raised")
        result(true)
      } else {
        NSLog("[redtick.window] native unimplemented method: %@", call.method)
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}

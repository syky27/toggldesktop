import Flutter
import UIKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register the BGAppRefresh task BEFORE the app finishes launching (iOS
    // requires BGTaskScheduler.register to happen here). The identifier must
    // match Info.plist BGTaskSchedulerPermittedIdentifiers and Dart's
    // kReconcileTaskId. The frequency for iOS is set here, not in Dart.
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "cz.syky.redtick.reconcile",
      frequency: NSNumber(value: 20 * 60))
    // Make the app's plugins (http / secure storage / shared_preferences /
    // live_activities) available inside the background isolate's engine.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

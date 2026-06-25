# RedtickLiveActivity — iOS Live Activity (Widget Extension)

This folder holds the SwiftUI Widget Extension that renders Redtick's
running-timer **Live Activity** (lock screen + Dynamic Island). The Dart side
(`lib/src/platform/live_timer_ios.dart`, via the `live_activities` plugin) pushes
`issue` / `description` / `project` / `startedAt` into the shared App Group; this
widget reads them and ticks its own elapsed clock.

The Swift/plist/entitlement files here are ready to use — but the **Xcode target
itself must be created once via the GUI** (the one step that can't be scripted
safely). Do this on a Mac with Xcode:

## One-time setup in Xcode

1. Open `ios/Runner.xcworkspace` in Xcode.
2. **File → New → Target… → Widget Extension.**
   - Product Name: **`RedtickLiveActivity`** (exactly).
   - **Check "Include Live Activity".** Uncheck "Include Configuration App Intent".
   - Finish → **Activate** the new scheme if prompted.
   Xcode creates the target, an "Embed Foundation Extensions" phase on Runner,
   and sample files in this folder.
3. **Use the committed sources, not the wizard's samples:**
   - Delete the wizard-generated sample Swift (e.g. `RedtickLiveActivityLiveActivity.swift`)
     — *Move to Trash*.
   - Make sure `RedtickLiveActivityBundle.swift` and `RedtickLiveActivity.swift`
     (the two files in this folder) are members of the **RedtickLiveActivity**
     target (File Inspector → Target Membership). If the wizard overwrote
     `RedtickLiveActivityBundle.swift`, restore it from git.
   - Keep this folder's `Info.plist` (it has `NSExtensionPointIdentifier` +
     `NSSupportsLiveActivities`).
4. **App Group on BOTH targets** (Signing & Capabilities → + Capability → App Groups):
   - `Runner` target → add **`group.cz.syky.redtick`** (already declared in
     `Runner/Runner.entitlements`; just confirm it shows checked).
   - `RedtickLiveActivity` target → add the **same** `group.cz.syky.redtick`
     (point its `CODE_SIGN_ENTITLEMENTS` at `RedtickLiveActivity.entitlements`).
5. **Deployment target:** set the `RedtickLiveActivity` target's *iOS Deployment
   Target* to **16.1** (ActivityKit minimum). The Runner app can stay at 13.0.
6. Build & run on an **iOS 16.2+ simulator** (iPhone 15/16 Pro for the Dynamic
   Island). Start a timer → the Live Activity appears; stop → it disappears.

## Notes
- No Flutter/CocoaPods wiring is needed in this extension — it's pure SwiftUI +
  ActivityKit, reading the App Group `UserDefaults` the plugin writes.
- The attributes struct here (`LiveActivitiesAppAttributes` + `prefixedKey`) must
  match the `live_activities` plugin exactly — don't rename it.
- Real-device builds additionally need the App Group registered on your Apple
  Developer account and matching provisioning; the simulator needs none of that.

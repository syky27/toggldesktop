# Live timer surfaces — iOS Live Activity & Android Live Update

Design §6. These are **glance surfaces while a timer runs**. The Dart side is
done and wired; the per-platform native pieces remain (they need on-device
testing and, for iOS, your Apple developer/Xcode setup, so they can't be built
or verified from the macOS-only dev loop).

## What's already done (Dart)
- **`lib/src/platform/live_timer.dart`** — `LiveTimerController` (the seam) +
  `LiveTimerInfo` payload (`guid`, `description`, `issueRef`, `project`,
  `startedAt`). Default impl logs; swap real implementations into
  `LiveTimerController.defaultFor()`.
- **Wired in `lib/src/ui/app.dart`**: a `ref.listen(timerStateProvider, …)`
  calls `start(info)` when a new running entry appears (or the issue changes)
  and `end()` on stop. It deliberately does **not** push every second — both
  surfaces render their own ticking clock from `startedAt`.

## iOS — Live Activity (ActivityKit + WidgetKit)
Needs a **Widget Extension target** added in Xcode (`ios/`):
1. Add target *Widget Extension* (e.g. `RedtickLiveActivity`), enable *Live
   Activities* (`NSSupportsLiveActivities = YES` in both Info.plists).
2. Define `ActivityAttributes` (static: issue, project, description; dynamic
   content: `startedAt`) and a SwiftUI lock-screen view + Dynamic Island
   (compact/expanded/minimal) — hourglass tile, issue, **`Text(timerInterval:)`**
   for the live clock, a **Stop** button.
3. Stop = an **App Intent** that deep-links back and calls `core.stop()`.
4. Bridge from Dart: easiest via the **`live_activities`** package
   (`start/update/end` with the attributes) → implement `IosLiveActivityController`
   and return it from `defaultFor()`. Requires iOS 16.1+ (Dynamic Island: iPhone 14 Pro+).
   Use SF Pro / monospaced digits.

## Android — Live Update (foreground ongoing notification)
1. A **foreground service** + ongoing notification: `setOngoing(true)` +
   `setUsesChronometer(true)` (live elapsed), app icon, issue, **Stop** + **Open**
   actions. Drive via `flutter_foreground_task` (or `flutter_local_notifications`).
2. Manifest: `FOREGROUND_SERVICE`, `POST_NOTIFICATIONS` (Android 13+), a service
   declaration; a notification channel.
3. Android 16+: **promote** it (status-bar chip) — request
   `POST_PROMOTED_NOTIFICATIONS` and set `setRequestPromotedOngoing` on a
   built-in style; gracefully no-op below 16.
4. Implement `AndroidLiveUpdateController` (start/end → start/stop the service +
   notification) and return it from `defaultFor()`. Use Roboto.

## Desktop
No live-activity equivalent — the in-app timer bar (and a future tray/menubar
item) is the glance surface. The default logging controller is correct here.

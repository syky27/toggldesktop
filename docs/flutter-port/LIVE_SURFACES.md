# Live timer surfaces — iOS Live Activity & Android Live Update

Design §6. These are **glance surfaces while a timer runs**. The Dart side is
done and wired. **iOS Live Activity is implemented (display-only v1).** The
**Android** Live Update is still deferred.

## What's already done (Dart)
- **`lib/src/platform/live_timer.dart`** — `LiveTimerController` (the seam) +
  `LiveTimerInfo` payload (`guid`, `description`, `issueRef`, `project`,
  `startedAt`). Default impl logs; swap real implementations into
  `LiveTimerController.defaultFor()`.
- **Wired in `lib/src/ui/app.dart`**: a `ref.listen(runningEntriesProvider, …)`
  calls `start(info)` when a new running entry appears (or the issue changes)
  and `end()` on stop. It deliberately does **not** push every second — both
  surfaces render their own ticking clock from `startedAt`. A stable
  `_liveSurfaceKey` gates re-pushes to meaningful changes only.
- **Concurrent tracking (multi_task_settings):** with one timer it shows that
  entry; with several it shows an aggregate `LiveTimerInfo.aggregate` — title
  "N timers running", clock counting from the earliest start — through the same
  App-Group keys, so **no Swift widget changes** are needed. One Live Activity per
  timer is a possible future enhancement.

## iOS — Live Activity (ActivityKit + WidgetKit) — DONE (display-only v1)
Built via the **`live_activities`** package (Dart) + a hand-written SwiftUI
Widget Extension (native). Requires iOS **16.1+** (Dynamic Island: iPhone 14 Pro+).

- **Dart:** `lib/src/platform/live_timer_ios.dart` → `IosLiveActivityController`
  (init App Group `group.cz.syky.redtick`, `createActivity` on start /
  `endActivity` on stop, replaces the activity on issue-change, gated by
  `areActivitiesEnabled()`, all best-effort). Returned from
  `LiveTimerController.defaultFor()` on iOS.
- **Main app:** `ios/Runner/Info.plist` has `NSSupportsLiveActivities`;
  `ios/Runner/Runner.entitlements` declares the App Group; `CODE_SIGN_ENTITLEMENTS`
  is wired into all three Runner build configs.
- **Widget Extension:** `ios/RedtickLiveActivity/` — `RedtickLiveActivityBundle.swift`
  (`@main` bundle), `RedtickLiveActivity.swift` (`LiveActivitiesAppAttributes` +
  `ActivityConfiguration`: brand-red hourglass tile, `#issue · project`,
  description, and a self-ticking `Text(timerInterval:)` elapsed clock; lock
  screen + Dynamic Island compact/expanded/minimal). Tap opens the app (no
  in-widget Stop in v1). `Info.plist` + `RedtickLiveActivity.entitlements` included.
- **One manual step (per `ios/RedtickLiveActivity/README.md`):** the Widget
  Extension *target* must be created once in Xcode (File → New → Target → Widget
  Extension, "Include Live Activity"), then point it at the committed sources and
  enable the **same App Group** on both the Runner and the extension targets.
- **Cross-device:** a remote stop (the 30 s poll → `_reconcileRunning`) clears the
  running entry → `app.dart` fires `live.end()` → the activity ends. No extra work.

*Deferred follow-up:* an in-widget **Stop** button (an App Intent calling
`core.stop()`, iOS 17+).

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

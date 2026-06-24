# Platform features (Phase 5: FP-50 – FP-55)

The core exposes platform-adjacent events through `toggl_on_*` callbacks, now
surfaced as Dart streams on `CoreService` (`reminders`, `pomodoro`, `idle`,
`onlineState`). This doc records how each Phase-5 feature binds to those streams
and which plugin implements the OS-specific half. Desktop-only features are
no-ops on mobile.

| Issue | Feature | Core hook | Flutter plugin | Status |
|-------|---------|-----------|----------------|--------|
| FP-50 | System tray + window mgmt | `on_timer_state` (running/stopped icon) | `tray_manager`, `window_manager` | stream wired; plugin = follow-up (desktop only) |
| FP-51 | Global shortcuts | start/show actions | `hotkey_manager` | follow-up (desktop only) |
| FP-52 | Idle detection + dialog | `on_idle_notification` → `CoreService.idle` | platform channel / `desktop` impl | stream wired ✅; dialog UI = follow-up |
| FP-53 | Timeline / autotracker | `on_timeline`, autotracker rules | desktop window detection (core already has `get_focused_window_*`) | desktop-only; stub on mobile |
| FP-54 | Notifications (reminder/pomodoro) | `on_reminder`, `on_pomodoro*` → streams | `flutter_local_notifications` | streams wired + in-app banners ✅; OS notification = swap `NotificationPresenter` |
| FP-55 | Mobile background/foreground sync | `toggl_fullsync` on resume | `WidgetsBindingObserver` | foreground resync = follow-up |

## Notifications (FP-54) — implemented path

`CoreService` emits `reminders`/`pomodoro` streams; `app.dart` listens and shows
an in-app banner **and** calls `NotificationPresenter.show()`. The default
presenter logs; to deliver real OS notifications, provide a presenter backed by
`flutter_local_notifications` (override `_notificationPresenterProvider`). The
indirection (see `lib/src/platform/notifications.dart`) keeps the FFI wiring
testable without a platform plugin.

## Idle (FP-52) — implemented path

`CoreService.idle` carries `IdleNotice` (guid, since, duration, started,
description). A desktop-only dialog should offer "discard idle time" / "keep" and
call the core's discard APIs (`toggl_discard_time_at` / `toggl_discard_time_and_continue`).

## Desktop tray/window/shortcuts (FP-50/51) — follow-up

Add `tray_manager` + `window_manager` + `hotkey_manager`, guarded by
`Platform.isLinux || isMacOS || isWindows`. Drive the tray icon from the
`timerState` stream. These are pure desktop concerns and remain no-ops on mobile.

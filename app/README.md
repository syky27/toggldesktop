# Redtick — Flutter app

One Flutter codebase (iOS, Android, macOS, Windows, Linux) talking to **Redmine
directly over HTTP** — no native core. The Redmine REST contract is documented in
`../docs/flutter-port/REDMINE_API_CONTRACT.md`; the broader port notes live under
`../docs/flutter-port/`.

## Architecture

```
lib/src/data/        Pure-Dart Redmine backend (RedmineApiClient + RedmineService)
lib/src/models/      Dart models (TimeEntry, account, …)
lib/src/state/       Riverpod providers + per-platform settings/storage
lib/src/ui/          screens (login, timer, list, editor, calendar, settings) + widgets
lib/src/platform/    notifications, live activity, background reconcile hooks
```

The service polls/writes Redmine time entries (running timer = an entry with the
`toggl_start`/`toggl_stop`/`toggl_guid` custom fields) and exposes the state as Dart
streams → Riverpod providers → widgets. The API key is kept in the OS keychain via
`flutter_secure_storage`; offline writes are queued and retried.

## Prerequisites

- Flutter stable (developed against **3.44.3**; the same version is pinned in CI).
- **Linux desktop** build deps: `clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev`.
- **macOS/Windows**: just the standard Flutter desktop toolchain (Xcode / Visual
  Studio "Desktop development with C++").

## Build & run

```bash
flutter pub get
flutter run -d macos            # or windows / linux / chrome / a device

flutter analyze
flutter test                    # the full suite under test/ (pure Dart)

flutter build macos --release   # or windows / linux
```

## CI / releases

GitHub Actions live in `../.github/workflows/`:

- **`desktop-ci.yml`** — on every push/PR: `flutter analyze` + `flutter test`, then a
  release-mode build on macOS, Windows, and Linux (uploads a raw bundle as a sanity
  artifact).
- **`desktop-release.yml`** — on a `v*` tag (or manual dispatch): builds and packages
  a polished installer per platform — **Linux AppImage**, **macOS `.dmg`** (signed +
  notarized when secrets present), **Windows Inno Setup `.exe`** — and attaches them
  to a draft GitHub Release. Packaging inputs live in `packaging/`
  (`linux/redtick.desktop`, `linux/AppRun`, `windows/redtick.iss`).
- **`ios-release.yml`** — on a `v*` tag: signs the iOS app (+ Live Activity
  extension) and uploads to **TestFlight** (fastlane `gym` + `upload_to_testflight`).
- **`android-release.yml`** — on a `v*` tag: builds a signed **AAB** + split **APKs**;
  attaches the APKs to the same draft GitHub Release (sideload) and, when the Play
  service-account secret is set, uploads the AAB to **Google Play** (fastlane
  `supply`). See `../docs/ANDROID_RELEASE.md`.

All signing is **gated on repo secrets** (forks / secret-less runs skip cleanly).
macOS/iOS signing is documented in `../docs/RELEASE_SIGNING.md`, Android in
`../docs/ANDROID_RELEASE.md`. Windows and Linux installers are not code-signed yet.

## Notes

- App launcher icons and the cold-start splash are generated from
  `assets/icon/` + `assets/splash/`. Regenerate with
  `dart run tool/generate_icons.dart && dart run flutter_launcher_icons` and
  `dart run flutter_native_splash:create`.

# Android release & signing

Android ships **signed APKs on the GitHub Release** (for sideloading) and, when a
Google Play service-account secret is present, a **signed AAB to Google Play** via
fastlane `supply`. Like iOS/macOS, everything is **gated on signing secrets**:
forks and secret-less runs skip the signed build cleanly. iOS/macOS signing lives
in [`RELEASE_SIGNING.md`](RELEASE_SIGNING.md).

- App id / package: `cz.syky.redtick.redtick`
- Build config: `app/android/app/build.gradle.kts`
- Workflow: `.github/workflows/android-release.yml`
- Fastlane lane: `app/fastlane/Fastfile` → `platform :android`, lane `:beta`

## The upload key (read this first)

Google Play uses **Play App Signing**: Google holds the real *app signing key*; you
upload builds signed with your *upload key*. The upload key here is a standard Java
keystore.

> ⚠️ **Back up the keystore + passwords offline.** If you lose the upload key *and*
> Play App Signing is **not** enabled for the app, you can never update the app
> again. With Play App Signing on, a lost upload key can be reset via Play Console,
> but don't rely on that — keep an offline backup (password manager + encrypted
> copy of the `.jks`).

### Generate the upload keystore (one-time, local)

```bash
keytool -genkey -v -keystore ~/keys/redtick-upload-keystore.jks \
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 \
  -alias redtick-upload -dname "CN=Redtick, O=cz.syky, C=CZ"
```

Record the **store password** and **key password**.

## Local release builds

Create `app/android/key.properties` (already git-ignored — verify with
`git check-ignore app/android/key.properties`). **Never commit it.**

```properties
storePassword=<store password>
keyPassword=<key password>
keyAlias=redtick-upload
storeFile=/absolute/path/to/redtick-upload-keystore.jks
```

`build.gradle.kts` loads this and signs `release` builds with it; if `key.properties`
is **absent** it falls back to the debug key, so `flutter run --release` and
secret-less CI still work.

```bash
cd app
flutter build apk --release --split-per-abi   # sideload / GitHub Release
flutter build appbundle --release             # Google Play

# Confirm the signer is the upload key (not "Android Debug"):
apksigner verify --print-certs \
  build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# Sideload onto a connected device:
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

`targetSdk` resolves to **36** via Flutter 3.44.3 — already ≥ Google Play's 2026
minimum (`targetSdk 35`). `minSdk` is 23 (`flutter_secure_storage`).

## CI secrets (GitHub → Settings → Secrets and variables → Actions)

| Secret | Contents |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | `base64 -i ~/keys/redtick-upload-keystore.jks \| tr -d '\n'` |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore `storePassword` |
| `ANDROID_KEY_ALIAS` | `redtick-upload` |
| `ANDROID_KEY_PASSWORD` | the key password |
| `GOOGLE_PLAY_JSON_KEY_BASE64` | *(later — Play only)* base64 of the Play service-account JSON |

```bash
gh secret set ANDROID_KEYSTORE_BASE64 --repo syky27/redtick \
  --body "$(base64 -i ~/keys/redtick-upload-keystore.jks | tr -d '\n')"
gh secret set ANDROID_KEYSTORE_PASSWORD --repo syky27/redtick --body '<store password>'
gh secret set ANDROID_KEY_ALIAS        --repo syky27/redtick --body 'redtick-upload'
gh secret set ANDROID_KEY_PASSWORD     --repo syky27/redtick --body '<key password>'
```

## How a release runs

A `v*` tag (or `workflow_dispatch`) triggers `android-release.yml`:

1. Decode the keystore + write a CI `key.properties`.
2. `flutter build appbundle --release` (AAB) + `flutter build apk --release
   --split-per-abi` (APKs). Version from the tag; `versionCode = GITHUB_RUN_NUMBER`
   (monotonic — Play requires a strictly increasing code).
3. Attach the APKs to the **same draft GitHub Release** the desktop workflow creates
   for that tag (matched by tag → coalesces; the Android section of the release notes
   lives in `desktop-release.yml`'s body). The desktop release job runs later (macOS
   notarization), so the draft is typically created here first and updated there. If
   the two ever race into duplicate drafts, delete the empty one before publishing.
4. **If** `GOOGLE_PLAY_JSON_KEY_BASE64` is set: `fastlane android beta` uploads the
   AAB to the Play **internal** track as a *draft* release.

`workflow_dispatch` on a branch (not a tag) builds but skips the GitHub Release job —
use it for a dry run.

## Google Play go-live (later — currently blocked)

The existing developer account (**AJTY, s.r.o.**) was **removed by Google on
2024-11-13** for not completing organization verification. Sideloaded APKs work
regardless; Play distribution is blocked until it's reinstated.

1. **Reinstate the account** — in Play Console, *View details* on the removal banner
   and complete **organization verification** (a D-U-N-S number matching the legal
   entity). Use the 90-day appeal/extension if offered. If unrecoverable, register a
   new org account ($25 + D-U-N-S). As an *organization* account it is exempt from
   the "12 testers / 14 days" closed-testing rule and can publish straight to
   production.
2. Create the app listing + content/data-safety declarations.
3. Google Cloud → create a **service account**, download a JSON key; in Play Console
   → *Users and permissions*, grant it release permissions. Set
   `GOOGLE_PLAY_JSON_KEY_BASE64`.
4. First AAB to the **internal** track (this enables Play App Signing). Promote to
   **production** when ready; the **internal testing** track is the TestFlight
   equivalent for testers (install via a Play link).

Optional knob: `GOOGLE_PLAY_TRACK` env (default `internal`) selects the lane's track.

## Maintenance

- The upload key is valid ~27 years (`-validity 10000`). Keep the offline backup.
- If the upload key is compromised, rotate it via Play Console (*App integrity →
  Upload key certificate → Request upload key reset*) and re-set the CI secrets.
- R8/resource shrinking is currently **off** (no keep rules authored). If enabled
  later, add `app/android/app/proguard-rules.pro` and verify a release build + the
  plugins (`flutter_secure_storage`, `flutter_local_notifications`, `workmanager`,
  `live_activities`) still work.

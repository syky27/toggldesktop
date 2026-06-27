# Release signing & notarization (iOS + macOS)

Both platforms sign **directly** from `.p12` secrets — no fastlane `match`, no
certificates repo. (match was tried first but proved too fragile on an Apple
account with pre-existing certs; the history is in git.)

- **macOS → Developer ID** (`desktop-release.yml`, macOS leg): the Developer ID
  Application cert is imported from a `.p12` secret into an ephemeral keychain,
  the app is deep-signed with the Hardened Runtime (`codesign --options runtime`),
  then notarized (`notarytool`) and stapled. App Sandbox stays **off** (idle
  detection needs system-wide `CGEventSource`); notarization is fine with it off.
- **iOS → TestFlight** (`ios-release.yml`): the Apple Distribution cert is
  imported from a `.p12` secret the same way; the App Store provisioning profiles
  for both bundle ids are fetched **read-only** via the App Store Connect API key
  (`get_provisioning_profile`), then `gym` archives and `upload_to_testflight`
  uploads. Runs on **macos-26 / Xcode 26** — Apple requires the iOS 26 SDK for
  uploads (older SDKs are rejected with a 409).

One App Store Connect API key drives notarization, profile fetch, and TestFlight
upload. Everything is **gated on the signing secrets being present** — forks and
secret-less runs fall back to unsigned (macOS) / skip (iOS), so the public CI
surface never needs secrets.

## Bundle identifiers
- main app: `cz.syky.redtick.redtick`
- Live Activity extension: `cz.syky.redtick.redtick.RedtickLiveActivity`
- App Group (both targets): `group.cz.syky.redtick`

## GitHub repo secrets

| Secret | Contents |
|---|---|
| `ASC_KEY_P8_BASE64` | base64 of the App Store Connect API key `.p8` |
| `ASC_KEY_ID` | the API Key ID |
| `ASC_ISSUER_ID` | the API Issuer ID |
| `APPLE_TEAM_ID` | 10-char Team ID (`CDMJRT8WJB`) |
| `MACOS_CERT_P12_BASE64` | base64 of the **Developer ID Application** `.p12` (cert + key) |
| `MACOS_CERT_PASSWORD` | that `.p12`'s password |
| `MACOS_KEYCHAIN_PASSWORD` | any random string (ephemeral CI keychain; reused by iOS) |
| `IOS_DIST_CERT_P12_BASE64` | base64 of the **Apple Distribution** `.p12` (cert + key) |
| `IOS_DIST_CERT_PASSWORD` | that `.p12`'s password |

Set a base64 secret with, e.g.:
`gh secret set MACOS_CERT_P12_BASE64 --repo syky27/redtick --body "$(base64 -i DeveloperID.p12 | tr -d '\n')"`

## One-time prerequisites (Apple side)
1. **App Store Connect API key** (Users and Access → Integrations → App Store
   Connect API, role App Manager). Download the `.p8` once; record Key ID + Issuer ID.
2. **App IDs + App Group + ASC app record**: register `cz.syky.redtick.redtick`
   and `…​.RedtickLiveActivity` with the **App Groups** capability assigned to
   `group.cz.syky.redtick`; create the App Store Connect app record for the main id.
3. **Certificates** (export each cert **with its private key** from Keychain
   Access → My Certificates → *Export 2 items* → `.p12`):
   - **Developer ID Application** → `MACOS_CERT_P12_BASE64` / `MACOS_CERT_PASSWORD`.
   - **Apple Distribution** → `IOS_DIST_CERT_P12_BASE64` / `IOS_DIST_CERT_PASSWORD`.
   `security import` accepts a Keychain-exported (legacy) `.p12` directly.
4. **App Store provisioning profiles** for both bundle ids must exist on the
   portal — the iOS lane fetches them read-only and does not create them. They
   currently exist (named `match AppStore …` from the original setup). **They
   expire ~yearly**: when that happens, regenerate them (Xcode/portal, or run the
   iOS lane's `get_provisioning_profile` with `readonly: false` once) — see the
   maintenance note below.

## How a release runs
A `v*` tag (or `workflow_dispatch`) triggers both workflows:
- `desktop-release.yml` → macOS (signed+notarized `.dmg`) + Windows + Linux on a
  draft GitHub Release.
- `ios-release.yml` → iOS app + Live Activity extension → TestFlight (build number
  = the workflow run number, which is monotonic).

When you **publish** the resulting draft release, `update-cask.yml` fires on the
`release: published` event, downloads the macOS `.dmg`, recomputes its sha256, and
commits the bumped `version` + `sha256` to `Casks/redtick.rb` on `master` — so the
Homebrew cask tracks releases automatically (no extra secret; it pushes to this same
repo with `GITHUB_TOKEN`).

## Verification
- **macOS**: `codesign --verify --deep --strict --verbose=2 Redtick.app`;
  `spctl -a -vvv -t install Redtick.app` → *Notarized Developer ID*;
  `xcrun stapler validate` on the app + dmg; offline launch on a clean Mac.
- **iOS**: the run logs "Successfully uploaded the new binary to App Store
  Connect"; the build appears in App Store Connect → Redtick → TestFlight.

## Maintenance notes
- **Certs**: Developer ID and Apple Distribution certs are account-wide and last
  ~5 years. When one is rotated, re-export the `.p12` and update the secret.
- **Profiles**: App Store profiles expire ~yearly. The iOS lane uses
  `get_provisioning_profile(readonly: true)` (it won't regenerate). To renew,
  temporarily set `readonly: false` in `app/fastlane/Fastfile` and run once (the
  API key has rights to create profiles), or recreate them in Xcode/the portal.
- **Xcode/SDK**: Apple periodically bumps the required SDK. If uploads start
  failing with a 409 "SDK version" error, bump the iOS runner image / Xcode in
  `ios-release.yml`.

# Release signing & notarization (iOS + macOS)

Two distinct mechanisms (because Developer ID and App Store certs behave differently):

- **iOS → TestFlight** uses **fastlane match** (Apple Distribution cert + App Store
  provisioning profiles for the app **and** the Live Activity extension), stored
  encrypted in a **separate private repo**, consumed read-only by CI.
  Workflow: `ios-release.yml`.
- **macOS → Developer ID** uses the Developer ID Application cert supplied directly
  as a **`.p12` secret** (NOT match — `match` cannot reliably create/verify
  Developer ID certs, the App Store Connect API doesn't list them). The app is
  deep-signed with Hardened Runtime, notarized, and stapled.
  Workflow: `desktop-release.yml` (macOS leg).

Both notarize/upload with **one App Store Connect API key**. Everything is **gated
on the signing secrets being present**: until you finish setup, releases keep
building **unsigned** (macOS) / skip TestFlight (iOS). No CI breakage meanwhile.

> ⚠️ **NEVER run `fastlane match nuke`.** It revokes **all** match-managed certs and
> profiles **account-wide** — including your other apps' (e.g. the `cz.ajty.*`
> profiles). It is not scoped to Redtick. Use only the lanes/commands below.

---

## One-time setup (once, on a Mac signed into the Apple account)

### 1. App Store Connect API key  (shared by iOS + macOS)
App Store Connect → **Users and Access → Integrations → App Store Connect API** →
create a **Team key**, role **App Manager**. Download `AuthKey_XXXX.p8` (offered
once). Record the **Key ID** + **Issuer ID**. Note your **Team ID** (Apple
Developer → Membership).

### 2. macOS Developer ID certificate → `.p12`  (no match)
You likely already have a **Developer ID Application** cert (an account can hold a
limited number). Reuse one, or create a new one (Keychain Access CSR →
developer.apple.com → Certificates → **Developer ID Application**). Then in
**Keychain Access → My Certificates**, select the *"Developer ID Application: …"*
cert **and its private key** → right-click → **Export 2 items** → `.p12` with a
password (→ `MACOS_CERT_PASSWORD`).

### 3. iOS: register identifiers in the Developer portal  (match won't create these)
- **App Group** `group.cz.syky.redtick` (Identifiers → App Groups).
- **App IDs**, each with the **App Groups** capability assigned to that group:
  - `cz.syky.redtick.redtick` (main app)
  - `cz.syky.redtick.redtick.RedtickLiveActivity` (Live Activity extension)
- **App Store Connect app record** for `cz.syky.redtick.redtick` (Apps → +).

### 4. iOS: private certs repo + match bootstrap
Create a **private** repo, e.g. `gh repo create syky27/redtick-certs --private --add-readme`.
Pick a strong **match passphrase** (`MATCH_PASSWORD`; store it in a password
manager). Then bootstrap **once** (writable) from `app/`:
```bash
cd app
bundle install                       # also produces Gemfile.lock — commit it
export MATCH_GIT_URL=https://github.com/syky27/redtick-certs.git
export MATCH_PASSWORD=…
export APPLE_TEAM_ID=…                # 10-char Team ID
export FASTLANE_USER=…                # your Apple ID (interactive 2FA for creation)

bundle exec fastlane match appstore \
  -a cz.syky.redtick.redtick,cz.syky.redtick.redtick.RedtickLiveActivity \
  --readonly false
```
This creates/stores the Apple Distribution cert + both App Store profiles. CI
thereafter runs **read-only** and never mutates anything.
- If it errors *"You already have a current Distribution certificate"* (account at
  the limit), import your existing one instead of creating a new one:
  `bundle exec fastlane match import --type appstore` (supply the existing `.cer`
  + `.p12`), then re-run the `match appstore` line.

### 5. Add the GitHub repo secrets
`Settings → Secrets and variables → Actions`, or `gh secret set`:

**Shared**
| Secret | Value |
|---|---|
| `ASC_KEY_P8_BASE64` | `base64 -i AuthKey_XXXX.p8 \| tr -d '\n'` |
| `ASC_KEY_ID` | the Key ID |
| `ASC_ISSUER_ID` | the Issuer ID |
| `APPLE_TEAM_ID` | 10-char Team ID |

**macOS (Developer ID via .p12)**
| Secret | Value |
|---|---|
| `MACOS_CERT_P12_BASE64` | `base64 -i DeveloperID.p12 \| tr -d '\n'` |
| `MACOS_CERT_PASSWORD` | the `.p12` export password (step 2) |
| `MACOS_KEYCHAIN_PASSWORD` | any random string (ephemeral CI keychain) |

**iOS (match)**
| Secret | Value |
|---|---|
| `MATCH_PASSWORD` | the match passphrase |
| `MATCH_GIT_URL` | `https://github.com/syky27/redtick-certs.git` |
| `MATCH_GIT_BASIC_AUTHORIZATION` | `printf 'x-access-token:%s' <PAT> \| base64 \| tr -d '\n'` — a fine-grained PAT, **Contents: Read** on `redtick-certs` only |

`gh` example:
```bash
R=syky27/redtick
gh secret set MACOS_CERT_P12_BASE64 --repo $R --body "$(base64 -i DeveloperID.p12 | tr -d '\n')"
gh secret set ASC_KEY_P8_BASE64     --repo $R --body "$(base64 -i ~/Downloads/AuthKey_XXXX.p8 | tr -d '\n')"
gh secret set MACOS_KEYCHAIN_PASSWORD --repo $R --body "$(openssl rand -base64 24)"
# …and the plain-text ones with --body "<value>"
```

---

## How a release runs

A `v*` tag triggers **both** workflows (`workflow_dispatch` also available):
- `desktop-release.yml` → macOS app signed (Developer ID, Hardened Runtime),
  notarized, stapled, packaged into a notarized `.dmg` on the draft Release.
- `ios-release.yml` → builds the iOS app + extension, uploads to TestFlight
  (build number = workflow run number, always increasing).

---

## Verification

**macOS** (on the artifact):
```bash
codesign --verify --deep --strict --verbose=2 redtick.app
codesign -dvvv redtick.app 2>&1 | grep -E 'Authority=Developer ID Application|flags=.*runtime'
spctl -a -vvv -t install redtick.app        # → accepted, source=Notarized Developer ID
xcrun stapler validate redtick.app && xcrun stapler validate redtick-*.dmg
```
Best real test: download the `.dmg` **in a browser** (so quarantine is applied),
copy the app to /Applications on a clean Mac, go **offline**, and launch — it must
open with no Gatekeeper prompt.

**iOS**: the run log shows both profiles installed and the `.appex` signed with the
**extension's** profile; a new build appears in App Store Connect → Redtick →
TestFlight (Processing → Ready to Test).

---

## Notes & gotchas
- **Never `fastlane match nuke`** (see the warning above) — account-wide.
- `match` is **read-only in CI** — only the step-4 bootstrap creates certs.
- The **Live Activity extension** needs its **own** App Store profile and the same
  App Group on **both** App IDs; signing it with the main app's profile fails.
- macOS uses the **Developer ID** cert; the App Sandbox stays **off** (idle
  detection). Notarization is fine with the sandbox off — it only needs the
  Hardened Runtime, applied via `--options runtime` at sign time.
- Developer ID certs are **account-wide and limited** — reuse an existing one if
  you can rather than creating new ones.
- Commit the `Gemfile.lock` from your bootstrap `bundle install` to pin fastlane.
- After the first verified signed macOS release, drop the "unsigned / `xattr -dr
  com.apple.quarantine`" workaround from the `desktop-release.yml` release notes.

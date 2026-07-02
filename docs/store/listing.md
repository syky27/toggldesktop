# Store listing copy — Redtick browser extension

Ready-to-paste text for the Chrome Web Store and Firefox AMO listings. Keep it in sync with
`extension/manifest.json` and `docs/store/privacy-policy.md`.

---

## Name

> Redtick — Start timer on Redmine issue

(66 chars — within Chrome's 75-char limit. Matches `manifest.json`.)

## Short summary / subtitle (Chrome: max 132 chars)

> Adds a "Start in Redtick" button to Redmine issue pages that starts a timer in the
> Redtick desktop app.

## Category

- **Chrome Web Store:** Workflow & Planning (Productivity)
- **Firefox AMO:** Productivity / Tabs & Workflow

## Language

English

## Detailed description

> Redtick is a time tracker for Redmine. This companion extension adds a **▶ Start in
> Redtick** button to every Redmine issue page. One click starts a timer on that issue in
> the **Redtick desktop app** — no copy-pasting issue numbers.
>
> **Requires the free Redtick desktop app** (macOS, Windows, or Linux) installed and
> running. The button opens a local `redtick://` link that the app handles; the extension
> itself never talks to Redmine's API and never sees your credentials.
>
> How it works:
> 1. Install the Redtick desktop app and this extension.
> 2. Open the extension's Settings and enter your Redmine URL (for example
>    `https://redmine.example.com`), then grant access to that one site.
> 3. Open any issue on that Redmine and click **▶ Start in Redtick**. The desktop app
>    comes to the front and starts tracking that issue (or, in multi-task mode, asks
>    whether to start a second concurrent timer).
>
> Privacy-first: the extension only stores the Redmine host you configure, runs only on
> that host, and sends nothing to any server. See the privacy policy for details.
>
> Not affiliated with, sponsored by, or endorsed by Redmine or its trademark holder.
> "Redmine" is used only to describe compatibility.

## Single-purpose description (Chrome requires this)

> The extension has one purpose: add a button to Redmine issue pages that starts a timer
> for that issue in the Redtick desktop app via a local `redtick://` link.

## Permission justifications (Chrome "Privacy practices" tab)

- **`storage`** — Persists the single Redmine host the user configures on the Settings
  page, so the button runs on the right site across sessions.
- **`scripting`** — Registers the button-injecting content script scoped to only the
  user's configured Redmine host (via `scripting.registerContentScripts`), avoiding a
  broad install-time host permission.
- **Host permission (`optional_host_permissions: *://*/*`, requested at runtime)** —
  Requested only for the exact Redmine host the user enters, and only when they click
  **Save & enable**. It is required to inject the button on that Redmine's issue pages.
  It is never requested for any other site.

## Data-use disclosures (Chrome) / data collection (Firefox)

- Does the extension collect user data? **No data is transmitted or sold.** The only value
  stored is the user-entered Redmine host, kept locally on the device.
- Certify compliance with **Limited Use**: yes — no data leaves the device; nothing is
  sold or transferred; no use beyond the single purpose above.
- Firefox `browsingActivity` consent: the extension reads the current issue page's
  URL/host on the configured Redmine to build the local `redtick://` link; this is not
  sent off-device.

## Privacy policy URL

Publish `docs/store/privacy-policy.md` at a public URL and paste it here, e.g.:

> https://github.com/syky27/redtick/blob/master/docs/store/privacy-policy.md

(GitHub Pages gives a cleaner URL if preferred.)

## Support / homepage

- Homepage: https://github.com/syky27/redtick
- Support: https://github.com/syky27/redtick/issues
- Email: redtick@syky.cz  _(confirm this is a monitored inbox before submitting)_

## Trademark disclaimer (include in both listings)

> Not affiliated with or endorsed by Redmine. "Redmine" is a trademark of its respective
> owner and is used here only to indicate compatibility.

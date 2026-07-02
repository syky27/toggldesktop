# Redtick browser extension — Privacy Policy

_Last updated: 2026-07-02_

The **Redtick — Start timer on Redmine issue** browser extension adds a
**▶ Start in Redtick** button to Redmine issue pages. Clicking it launches a local
`redtick://start?issue=<id>&host=<host>` link that the Redtick desktop app on your own
computer handles.

## Short version

The extension **does not collect, transmit, or sell any personal data**. It has no
servers, no analytics, and no third-party services. It never reads your Redmine
credentials or cookies and never calls Redmine's API.

## What the extension stores

- **Your Redmine host** (for example `redmine.example.com`) — the value you type on the
  extension's Settings page. It is saved with the browser's `storage.local` API on your
  device so the button knows which site to run on. It is not sent anywhere.

That is the only piece of information the extension stores.

## What the extension sends, and where

When you click **▶ Start in Redtick** on an issue page, the extension opens a
`redtick://start?issue=<id>&host=<host>` link, where:

- `<id>` is the numeric issue id read from the page URL (`/issues/<id>`), and
- `<host>` is the host of the page you are on (`location.host`).

The operating system routes that link to the **Redtick desktop app running on the same
computer**. No data is sent to the extension author, to Redmine, or to any remote server.
The desktop app verifies that `<host>` matches the Redmine you are logged into before it
does anything.

## Permissions and why they are used

- **`storage`** — to save the Redmine host you configure (see above).
- **`scripting`** — to register the button-injecting content script **scoped to only the
  Redmine host you entered**, instead of requesting access to all sites up front.
- **Host access (optional, requested at runtime)** — granted only for the specific Redmine
  host you enter on the Settings page. The extension asks for it when you click **Save &
  enable**; it is never requested for other sites.

## Data collection disclosure (Firefox)

The manifest declares `browsingActivity` under Firefox's built-in data-consent system.
This is because the extension reads the current page's URL/host on your configured Redmine
in order to build the `redtick://` link. That information is used **only** to launch the
local desktop app and is **not** transmitted off your device.

## Analytics, third parties, and data sharing

None. The extension contains no analytics, no tracking, no remote code, and no third-party
libraries or services. No data is shared with anyone.

## Data retention

The only stored value (your Redmine host) lives in the browser's local extension storage.
It is removed when you uninstall the extension or clear its data.

## Changes to this policy

If this policy changes, the updated version will be published at this URL and the "Last
updated" date above will change.

## Contact

- Issues / questions: <https://github.com/syky27/redtick/issues>
- Email: redtick@syky.cz

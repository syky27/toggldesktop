# Browser-extension store submission checklist

The extension currently ships **self-hosted**: a Chromium `.zip` (load-unpacked) and an
AMO-signed **unlisted** Firefox `.xpi`, both attached to each GitHub Release. Publishing it
as a **public store listing** on the Chrome Web Store and Firefox AMO is a separate effort;
this is what it takes.

Copy for every field lives in [`listing.md`](listing.md); the privacy policy is
[`privacy-policy.md`](privacy-policy.md).

## What I cannot do for you (manual)
- Create the store developer accounts.
- Pay Google's one-time **$5** Chrome developer fee.
- Upload packages / assets and click "Submit for review" in the dashboards.
- Capture real screenshots (need the extension running against a live Redmine).

Everything else (a compliant MV3 package, listing text, permission justifications, privacy
policy) is ready in this repo.

## 0. Shared prerequisites (do once)
- [ ] **Publish the privacy policy** at a public URL (GitHub blob works; GitHub Pages is
      cleaner) and note the URL.
- [ ] **Screenshots** — capture 1–5. At minimum: (a) a Redmine issue page showing the
      **▶ Start in Redtick** button, (b) the extension Settings page.
      Save at **1280×800** (preferred) or 640×400, PNG.
- [ ] **Chrome small promo tile** — create **440×280** PNG (required by Chrome).
      Optional marquee **1400×560**.
- [ ] Confirm `redtick@syky.cz` (or another address) is a **monitored support inbox**.
- [ ] Grab the packaged zip from the GitHub Release (`redtick-browser-extension-v1.11.0.zip`).

### Asset spec quick-reference
| Asset | Chrome | Firefox AMO |
|---|---|---|
| Store icon | 128×128 PNG ✅ (in repo) | 128×128 PNG ✅ |
| Screenshots | 1–5 @ 1280×800 or 640×400 | ≥1 recommended |
| Small promo tile | **440×280 (required)** | n/a |
| Marquee | 1400×560 (optional) | n/a |
| Privacy policy URL | **required** | recommended (field provided) |

## 1. Chrome Web Store
- [ ] Register a developer account at the Chrome Web Store Developer Dashboard; pay the
      one-time **$5** fee.
- [ ] **Upload** `redtick-browser-extension-v1.11.0.zip` (already MV3 — no code changes).
- [ ] Fill **Store listing**: name, summary (≤132), detailed description, category
      (Workflow & Planning), language, screenshots, 128 icon, 440×280 promo tile.
      Mention it **requires the Redtick desktop app** so review doesn't fail it as
      non-functional.
- [ ] Fill **Privacy practices**: single-purpose description; justify `storage`,
      `scripting`, and the runtime host permission; complete data-use disclosures; certify
      **Limited Use**; paste the privacy-policy URL.
- [ ] Add the **Redmine trademark disclaimer** (in the description).
- [ ] Submit for review (typically a few business days).

## 2. Firefox AMO (public / listed)
- [ ] Create a free Mozilla account; accept the distribution agreement.
- [ ] Decide channel: the CI-signed XPI is **unlisted**. A public listing is a **listed**
      submission of the same source, same add-on id (`redtick@syky.cz`). Submit via the
      AMO dashboard (or `web-ext` with the listed channel).
- [ ] Upload the same source zip. Manifest is AMO-ready (`gecko.id`,
      `data_collection_permissions`, `strict_min_version`).
- [ ] Fill listing: name, summary, description, categories, screenshots, 128 icon,
      support email/site, privacy-policy URL, and the data-collection consent form matching
      `browsingActivity`.
- [ ] Source code: JS is plain/unminified → **no source upload required**.
- [ ] Submit; automated review runs, with possible manual follow-up.

## 3. Notes / gotchas
- **Versioning:** both stores reject re-uploads with a version already used. Use `1.11.0`
  and bump for each store update. The release CI stamps the extension version from the git
  tag.
- **External-app dependency:** the extension is inert without the Redtick desktop app.
  State this clearly in both descriptions.
- **No remote code / analytics** in the package — this keeps review fast on both stores.
- **Edge Add-ons** (optional, later): the same zip works; Microsoft's store is free and
  Chromium-compatible.

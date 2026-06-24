<h1 align="center">
  <img src="docs/redtick-wordmark.png" alt="Redtick" width="420">
</h1>

<h4 align="center">A Redmine-native time tracker — the Toggl Desktop experience, wired straight to your own <a href="https://www.redmine.org" target="_blank">Redmine</a>.</h4>

<p align="center">
  <img src="https://img.shields.io/badge/backend-Redmine-A11C1C?style=flat" alt="Redmine backend">
  <img src="https://img.shields.io/badge/built%20with-Claude%20Code-D97757?style=flat" alt="Built with Claude Code">
  <img src="https://img.shields.io/badge/macOS-verified-444?style=flat" alt="macOS verified">
  <img src="https://img.shields.io/badge/licence-BSD--3-green" alt="Licence BSD-3">
</p>

<p align="center">
  <a href="#about">About</a> •
  <a href="#built-with-claude-code">Built with Claude Code</a> •
  <a href="#how-it-works">How it works</a> •
  <a href="#redmine-setup-required-custom-fields">Custom fields</a> •
  <a href="#configure">Configure</a> •
  <a href="#build">Build</a> •
  <a href="#credits">Credits</a>
</p>

# About

**Redtick** is a community fork of [Toggl Desktop](https://github.com/toggl-open-source/toggldesktop) that swaps the Toggl cloud backend for **Redmine**. You keep the fast, friendly desktop timer, but every entry you track lands in your own Redmine instance instead of Toggl's servers.

No Toggl account. No third-party cloud. Your time data stays on the Redmine server you point it at.

What it does today (verified on macOS):

- **Log in with a Redmine URL + personal API key** — no passwords, no OAuth, no SSO.
- **Projects and your issues load automatically**, and you can **search any issue your token can see** — by issue number or by text, not just the ones assigned to you.
- **Start/stop a timer on a Redmine issue.** On stop it creates a Redmine time entry with `hours`, `spent_on`, `activity`, comments, and the exact start/stop timestamps stored in custom fields. Edits `PUT`, deletes `DELETE`.
- **Every entry must be linked to a Redmine issue** — the timer refuses to start without one.
- **Day calendar view** with draggable blocks: move/resize entries, click an empty slot to create one, click a block to edit. A timer that runs past local midnight is split into one entry per day so Redmine's per-day hours stay correct.
- **Activity picker** — choose a default activity in Preferences and override it per entry; activities are pulled live from Redmine.
- **Pause-on-idle**, reminders and Pomodoro carry over from Toggl Desktop. The idle prompt lets you keep or discard idle time.

# Built with Claude Code

This fork was implemented **almost entirely by [Claude Code](https://claude.com/claude-code)** (Anthropic) — the Redmine backend retarget, the removal of Toggl-only cruft, the calendar/issue-picker UI, and this RedTick rebrand. Every commit on this branch is Claude-attributed by design. Treat the code accordingly: it has been built and verified, but it is AI-authored and benefits from review before you rely on it.

# How it works

Toggl's hardcoded backend hosts are replaced with a **single, runtime-configurable Redmine base URL** (`src/urls.cc`). Every endpoint the app used to spread across separate Toggl hosts now resolves to that one Redmine base:

```cpp
std::string API()        { return BaseURL(); }
std::string SyncAPI()    { return BaseURL(); }
std::string WebSocket()  { return BaseURL(); }
// …all resolve to the configurable Redmine base
```

The base URL is set at runtime on the login screen via `urls::SetBaseURL()` and persisted beside the local database, so it survives restarts. For headless / CI runs it falls back to the **`TOGGL_REDMINE_URL`** environment variable. Nothing is hardcoded to an internal host. A small `RedmineClient` (`src/redmine_client.{h,cc}`) fans the login out across Redmine's `/users/current`, `/projects`, `/issues`, `/time_entries` and activity endpoints and assembles what the existing model loader expects.

# Redmine setup: required custom fields

Before you track anything, your Redmine instance needs **three time-entry custom fields**. Redtick stores a little extra data on every time entry through them, and without them you lose exact clock times and reliable editing/deletion. Create them once, in **Administration → Custom fields → New custom field → Time entries**:

| Name (exact) | Format | Holds | Required? |
| --- | --- | --- | --- |
| `toggl_start` | Text | Exact start time, ISO 8601 (e.g. `2026-06-24T09:03:11+02:00`) | No |
| `toggl_stop`  | Text | Exact stop time, ISO 8601 | No |
| `toggl_guid`  | Text | The app's stable id for the entry (used to match edits/deletes) | No |

Setup notes:

- **The names must match exactly** — `toggl_start`, `toggl_stop`, `toggl_guid`. Redtick resolves the fields *by name* at login (it never assumes hardcoded field ids), so a typo means the field won't be found.
- **Format must be `Text`** (a plain string). The values are ISO 8601 timestamps and a GUID, both written and read as text.
- **Leave "Required" unchecked.** Redtick fills these in automatically, but entries logged from the Redmine web UI won't have them — making them required would break manual logging.
- **Tick the projects** the field applies to (or "for all projects"), and keep it **visible** so the API key can read it back.
- You need Redmine **admin rights to create custom fields**, but you do *not* need admin rights to use them afterwards — a normal user's API key reads the ids straight off its own time entries.

## Why these fields are needed

A native Redmine time entry only records **`hours`** and **`spent_on`** (a calendar *date*, not a clock time), plus an activity and a comment. That's lossy for a desktop timer in two ways, and the custom fields close both gaps:

- **Exact start/stop times.** Redmine has no concept of "started at 09:03, stopped at 10:47" — only "1.73 hours on 2026-06-24". `toggl_start` / `toggl_stop` preserve the precise timestamps so the day calendar can place and resize blocks correctly. When they're absent (e.g. an entry typed into the Redmine web UI), Redtick falls back to synthesizing a start time from `spent_on` + `hours`, so the block lands on the right day but at an approximate time.
- **Stable identity for edits and deletes.** Redmine's own time-entry id changes meaning between machines and re-syncs; `toggl_guid` carries the app's own id so an edit (`PUT`) or delete (`DELETE`) reliably targets the *same* entry instead of creating duplicates.

If you skip the fields entirely, tracking still works — new entries are created with the right hours and date — but exact times are approximated and idempotent editing is degraded. Creating the three fields is a one-time, five-minute step that makes the experience lossless.

## Can I hide these fields in the Redmine web UI?

First, a clarification: these are **time-entry** custom fields, not **issue** custom fields. They **never appear on the issue edit form** — only on Redmine's "Log time" / time-entry edit form. So if you just want the issue screen kept clean, there's nothing to do.

To hide them from the time-entry form itself, your only lever is the field's **"Visible"** setting (all users vs. specific roles). Redmine has **no "expose in the API but hide from the form" switch** — the visibility setting gates the REST API exactly as it gates the UI. And Redtick *reads these values back through the API*, so:

- **Hiding them from other users is fine** — restrict "Visible" to the role(s) your tracking accounts hold, and everyone else stops seeing them with no functional impact.
- **Do not hide them from the account whose API key Redtick uses.** If that user can't see the fields, the API omits them, and Redtick degrades: it falls back to *synthesizing* start times from `spent_on` + `hours` (losing the exact clock times), and — for non-admins — can fail to resolve the field ids by name and fall back to instance-specific defaults that may be wrong.

In short: you can scope visibility to the tracking users, but you can't make the fields invisible *and* still readable by the same API key. The practical choice is to leave them visible to the tracking accounts and accept a small amount of clutter on the log-time form.

# Configure

0. **One-time:** make sure the three [time-entry custom fields](#redmine-setup-required-custom-fields) exist on your Redmine instance.
1. Launch Redtick.
2. On the login screen, enter the URL of your Redmine instance (e.g. `https://redmine.example.com`) and your personal **API key** (Redmine → *My account* → *API access key*).
3. Start tracking — entries sync to that Redmine backend.

Headless / scripted use:

```bash
export TOGGL_REDMINE_URL="https://redmine.example.com"
./TogglDesktop
```

# Build

Only the **Qt UI + C++ core** are built in this fork (the legacy macOS/Swift and Windows/WPF front-ends are not maintained here). macOS is the verified path; Linux uses the same CMake build.

## macOS (verified)

One command from the repo root — it installs any missing Homebrew dependencies, configures CMake, builds, and launches the app:

```bash
./run-mac.sh
```

Equivalent manual build (modern Homebrew Qt 5 / POCO / OpenSSL 3 / jsoncpp):

```bash
brew install pkg-config poco jsoncpp        # qt@5 + openssl@3 usually already present
cmake -S . -B build -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DCMAKE_PREFIX_PATH="$(brew --prefix qt@5);$(brew --prefix poco);$(brew --prefix jsoncpp)" \
  -DOPENSSL_ROOT_DIR="$(brew --prefix openssl@3)" \
  -DPOCO_INCLUDE_DIRS="$(brew --prefix poco)/include" \
  -DJSONCPP_INCLUDE_DIRS="$(brew --prefix jsoncpp)/include"
cmake --build build --target TogglDesktop -j8
# run from the build dir so it finds the bundled cacert.pem
cd build/src/ui/linux/TogglDesktop && ./TogglDesktop
```

The core links the **system OpenSSL 3**, so TLS to a modern Redmine works out of the box (the ancient bundled OpenSSL 1.0.1e is only used by the unmaintained Windows build).

## Linux

Qt 5.12+ modules: **QtWidgets** (with private headers), **QtNetwork**, **QtDBus**, **QtX11Extras**. Plus `libXScrnSaver` (`libxss-dev` / `libXScrnSaver-devel`) and POCO / OpenSSL 3 / jsoncpp.

```bash
sudo apt install build-essential libxss-dev libgl-dev libreadline-dev \
                 qtbase5-dev qtbase5-private-dev libqt5x11extras5-dev \
                 libpoco-dev libssl-dev libjsoncpp-dev
mkdir -p build && cd build
cmake ..
make -j8
./src/ui/linux/TogglDesktop/TogglDesktop
```

> Note: Qt **NetworkAuth is no longer required** — the Google/SSO OAuth paths were removed in this fork.

## Windows

The legacy WPF client is not maintained in this fork and the Qt UI on Windows is currently **untested**. Contributions welcome.

# Credits

Redtick is built on **[Toggl Desktop](https://github.com/toggl-open-source/toggldesktop)** by the Toggl team and open-source contributors, used under the **BSD-3-Clause** licence. Huge thanks to them — Redtick changes the backend and branding; the desktop client itself is their work. The original licence is retained in [`LICENSE`](LICENSE).

The Redmine integration and rebrand were authored with **[Claude Code](https://claude.com/claude-code)** (Anthropic).

Redtick is not affiliated with or endorsed by Toggl, Anthropic, or the Redmine project.

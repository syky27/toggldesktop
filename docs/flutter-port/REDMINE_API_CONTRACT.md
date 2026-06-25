# Redtick — Redmine REST contract

The pure-Dart backend (`app/lib/src/data/redmine_api_client.dart` +
`redmine_service.dart`) replaced the C++/FFI core. This is the contract it
implements — the endpoints, the Toggl-era custom-field scheme it preserves, and
the running-timer model. It is the reference for keeping the Dart implementation
faithful to how the existing **Qt** Redmine app stores time.

> Mined from the original C core (`src/redmine_client.cc`, `src/model/time_entry.cc`)
> and verified live against `servicedesk.sumanet.cz`.

## Auth
- The Redmine **API access key** is the only credential (no passwords).
- Sent as the `X-Redmine-API-Key` header. (The C core used HTTP basic-auth with
  the key as the username and `api_key` as the password; Redmine accepts both.)
- A `401/403` means a bad/expired key. The host must be the **exact** Redmine URL
  — the client follows redirects, but a `3xx` to a different host that drops the
  auth header will read as unauthorized.

## Data model mapping
Redmine has no workspaces and no "running entry" concept. The app maps:

| Redmine        | App model            |
|----------------|----------------------|
| project        | project (color by index) |
| **issue**      | the thing time is tracked against (`tid`/task) |
| time_entry     | a `TimeEntry`        |
| (none)         | a single synthetic workspace |

A Redmine `time_entry` is `hours` (decimal) logged against a `spent_on` **date** —
no clock times. Exact start/stop are carried in **custom fields**.

## Custom fields & schema resolution (critical)
Three time-entry custom fields hold the clock data; their **ids are
instance-specific** and resolved by **name** at login (defaults are the
known-good ids for the current backend):

| Name          | Default id | Holds |
|---------------|-----------:|-------|
| `toggl_start` | 12 | ISO-8601 UTC start (`yyyy-MM-ddTHH:mm:ssZ`) |
| `toggl_stop`  | 14 | ISO-8601 UTC stop; **empty ⇒ running** |
| `toggl_guid`  | 13 | UUID v4 for write idempotency |

Resolution (`_resolveSchema`): scan the user's own time entries' `custom_fields`
for those names; if any is still unresolved, fall back to
`GET /custom_fields.json` (admin-only on some instances → tolerate `403`). The
activity list + default activity (`Development`, else instance default, else
first active) are resolved the same way from
`GET /enumerations/time_entry_activities.json`. **Without correct ids, idempotency
and exact clock times break.**

## Reads
- `GET /users/current.json` — validate key, get user id/name/email.
- `GET /projects.json` — all projects (paged, 100/page).
- `GET /issues.json?assigned_to_id=me&status_id=open&sort=updated_on:desc` — cached
  "my open" set (capped 500); live search covers the rest.
- `GET /time_entries.json?user_id=me&from=<30d ago>` — recent entries.
- Issue picker: `GET /issues.json?{issue_id=<n>|subject=~<q>}&<scope>` where scope
  is `assigned_to_id=me&status_id=open` (mine), `…&status_id=*` (assigned), or
  `status_id=*` (all visible).
- **Pagination:** `limit=100&offset=N`, stop at `total_count` (or a `maxItems` cap).

For each entry, start/stop come from `toggl_start`/`toggl_stop`. Entries logged in
the Redmine web UI (no toggl fields) are **synthesized** from `spent_on` at 09:00
plus `hours`.

## Writes
`hours: 0` is accepted by this instance (a 21-second entry stores `0.0`). Keep a
tiny-epsilon fallback for stricter instances.

**Create** (`POST /time_entries.json`):
```json
{ "time_entry": {
  "issue_id": 23409,                 // or "project_id" when there's no issue
  "hours": 0,
  "spent_on": "2026-06-25",          // local calendar date of start
  "comments": "<description>",
  "activity_id": 6,
  "custom_fields": [
    {"id": 12, "value": "2026-06-25T08:00:00Z"},   // toggl_start
    {"id": 14, "value": ""},                        // toggl_stop ("" ⇒ running)
    {"id": 13, "value": "<uuid>"}                    // toggl_guid
  ]
}}
```
Returns `201` with `time_entry.id`.

**Update / stop / edit** (`PUT /time_entries/{id}.json`, returns `204`): send only
changed fields — `hours`, `comments`, `activity_id`, `issue_id`, `spent_on`, and a
`custom_fields` array for the changed toggl_* values. **Stop** = set `toggl_stop`
to now and finalize `hours = (stop−start)/3600`.

**Delete** (`DELETE /time_entries/{id}.json`, returns `204`).

## Running timer (cross-device source of truth)
Unlike the Qt/core app (which kept the running entry local and posted only on
stop), Redtick **posts on START** with `toggl_stop` empty. Therefore:

- **The running entry = the Redmine time_entry whose `toggl_stop` is empty.**
- On launch/refresh, find that entry → that's what's running (on any device).
- Elapsed is always computed from `toggl_start`, **never** from the provisional
  `hours` (which stays at the start value until stop).
- Enforce a single running entry (stop any existing open one before starting).
- The UI starts optimistically and reconciles with the server's open entry by
  `toggl_guid`.

## Timezones
`toggl_start`/`toggl_stop` are stored in **UTC** (ISO-8601 `…Z`) and parsed to
local for display. `spent_on` is the **local** calendar date of the start.

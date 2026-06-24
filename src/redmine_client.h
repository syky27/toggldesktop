// Copyright 2026 Toggl Desktop -> Redmine fork

#ifndef SRC_REDMINE_CLIENT_H_
#define SRC_REDMINE_CLIENT_H_

#include <string>
#include <utility>
#include <vector>

#include "Poco/Types.h"

#include "types.h"

namespace Json { class Value; }

namespace toggl {

// RedmineClient talks to a Redmine REST backend and assembles the result into
// the Toggl-shaped account JSON that User::LoadUserAndRelatedDataFromJSON()
// already knows how to parse, so the rest of the model/DB pipeline is unchanged.
//
// Mapping:
//   Redmine project    -> Toggl project
//   Redmine issue      -> Toggl task (this is what time is tracked against)
//   Redmine time_entry -> Toggl time entry
// A single synthetic workspace (id 1) is used because Redmine has no workspaces.
// Exact start/stop clock times are preserved in the time-entry custom fields
// toggl_start / toggl_stop (ids configured below); when absent (entries logged
// in the Redmine web UI) they are synthesized from spent_on + hours.
class RedmineClient {
 public:
    // Time-entry custom-field ids and the default activity id. These are
    // instance-specific Redmine enumeration ids, resolved by NAME at login
    // (see ResolveSchema, called from FetchAccountJSON). The initial values are
    // the known-good fallback for the current backend if resolution fails.
    static int kCustomFieldStart;  // toggl_start
    static int kCustomFieldStop;   // toggl_stop
    static int kCustomFieldGUID;   // toggl_guid

    // Default Redmine TimeEntryActivity id used when the user has not chosen one.
    static int kDefaultActivityID;

    // The instance's global TimeEntryActivity list as {id, name} pairs, captured
    // by ResolveSchema() at login. Shown in the editor + Preferences pickers.
    static const std::vector<std::pair<Poco::UInt64, std::string>> &Activities();

    // Build the Toggl-shaped account JSON document. `apiKey` authenticates as
    // the Redmine API key. `since` (unix seconds, 0 = full) bounds how far back
    // time entries are pulled.
    static error FetchAccountJSON(
        const std::string &apiKey,
        const Poco::Int64 since,
        std::string *out_json);

    // Live issue search. If `query` is all digits it is looked up by id
    // (issue_id=<query>), otherwise by subject substring (subject=~<query>);
    // always status_id=* so any assignee/closed issue is reachable, unlike the
    // assigned-only set cached at login. Fills `out_tasks` with a JSON array of
    // Toggl-shaped task objects (same shape as FetchAccountJSON's tasks).
    static error SearchIssuesJSON(
        const std::string &apiKey,
        const std::string &query,
        Json::Value *out_tasks);

 private:
    // Resolve kDefaultActivityID + the toggl_* custom-field ids by NAME from the
    // backend (activity "Development"; custom fields toggl_start/stop/guid),
    // keeping the defaults above on failure. `timeEntries` is the already-fetched
    // user time-entry array, scanned so non-admins (who can't read
    // /custom_fields.json) still learn the ids from their own entries.
    static void ResolveSchema(const std::string &apiKey,
                              const Json::Value &timeEntries);

    // Global TimeEntryActivity list, filled by ResolveSchema().
    static std::vector<std::pair<Poco::UInt64, std::string>> activities_;
};

}  // namespace toggl

#endif  // SRC_REDMINE_CLIENT_H_

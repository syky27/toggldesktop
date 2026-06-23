// Copyright 2026 Toggl Desktop -> Redmine fork

#ifndef SRC_REDMINE_CLIENT_H_
#define SRC_REDMINE_CLIENT_H_

#include <string>

#include "Poco/Types.h"

#include "types.h"

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
    // Custom field ids configured on Redmine time entries.
    static const int kCustomFieldStart;  // toggl_start
    static const int kCustomFieldStop;   // toggl_stop
    static const int kCustomFieldGUID;   // toggl_guid

    // Default Redmine TimeEntryActivity id used when the user has not chosen one.
    static const int kDefaultActivityID;

    // Build the Toggl-shaped account JSON document. `apiKey` authenticates as
    // the Redmine API key. `since` (unix seconds, 0 = full) bounds how far back
    // time entries are pulled.
    static error FetchAccountJSON(
        const std::string &apiKey,
        const Poco::Int64 since,
        std::string *out_json);
};

}  // namespace toggl

#endif  // SRC_REDMINE_CLIENT_H_

// Copyright 2026 Toggl Desktop -> Redmine fork

#include "redmine_client.h"

#include <cctype>
#include <sstream>
#include <string>

#include <json/json.h>  // NOLINT

#include "Poco/DateTime.h"
#include "Poco/DateTimeFormatter.h"
#include "Poco/DateTimeParser.h"
#include "Poco/LocalDateTime.h"
#include "Poco/Timespan.h"
#include "Poco/Timestamp.h"

#include "https_client.h"
#include "urls.h"
#include "util/formatter.h"

namespace toggl {

// Fallback time-entry custom-field ids and Development activity id for the
// configured backend. ResolveSchema() overwrites these at login by matching the
// backend's enumerations by NAME, so the app self-corrects if these
// instance-specific ids ever change.
int RedmineClient::kCustomFieldStart = 12;  // toggl_start
int RedmineClient::kCustomFieldStop = 14;   // toggl_stop
int RedmineClient::kCustomFieldGUID = 13;   // toggl_guid
int RedmineClient::kDefaultActivityID = 6;  // Development

static const Poco::UInt64 kSyntheticWorkspaceID = 1;
static const int kPageSize = 100;
// Match the app's ~30-day local time-entry retention.
static const int kTimeEntryWindowDays = 30;
// Cap the locally-cached issue set (a single dev can have thousands of open
// issues); the most-recently-updated ones are cached for offline/quick pick and
// live search (toggl_search_issues) reaches the rest.
static const int kMaxCachedIssues = 500;
// Cap live-search results so a broad subject match can't flood the dropdown.
static const int kMaxSearchResults = 50;

namespace {

// GET a single Redmine resource and parse the JSON response body.
error redmineGet(const std::string &apiKey,
                 const std::string &relative_url,
                 Json::Value *root) {
    HTTPRequest req;
    req.host = urls::API();
    req.relative_url = relative_url;
    // Redmine accepts the API key as the basic-auth username; the password is
    // ignored but must be non-empty for the client to attach credentials.
    req.basic_auth_username = apiKey;
    req.basic_auth_password = "api_key";

    HTTPResponse resp = TogglClient::GetInstance().Get(req);
    if (resp.err != noError) {
        return resp.err;
    }
    Json::Reader reader;
    if (!reader.parse(resp.body, *root)) {
        return error("Redmine: failed to parse response for " + relative_url);
    }
    return noError;
}

// GET a paginated Redmine collection, appending every page's `arrayKey` array
// into `out`.
error redmineGetPaged(const std::string &apiKey,
                      const std::string &path,
                      const std::string &query,
                      const std::string &arrayKey,
                      Json::Value *out,
                      int maxItems) {
    int offset = 0;
    while (true) {
        std::stringstream url;
        url << path << "?";
        if (!query.empty()) {
            url << query << "&";
        }
        url << "limit=" << kPageSize << "&offset=" << offset;

        Json::Value root;
        error err = redmineGet(apiKey, url.str(), &root);
        if (err != noError) {
            return err;
        }
        const Json::Value &arr = root[arrayKey];
        for (unsigned int i = 0; i < arr.size(); i++) {
            out->append(arr[i]);
        }
        int total = root.isMember("total_count")
            ? root["total_count"].asInt() : static_cast<int>(arr.size());
        offset += kPageSize;
        if (arr.size() == 0 || offset >= total) {
            break;
        }
        if (maxItems > 0 && static_cast<int>(out->size()) >= maxItems) {
            break;
        }
    }
    return noError;
}

// Read a custom field value (by id) from a Redmine entity's custom_fields array.
std::string customField(const Json::Value &entity, int id) {
    if (!entity.isMember("custom_fields")) {
        return "";
    }
    const Json::Value &cfs = entity["custom_fields"];
    for (unsigned int i = 0; i < cfs.size(); i++) {
        if (cfs[i]["id"].asInt() == id && cfs[i]["value"].isString()) {
            return cfs[i]["value"].asString();
        }
    }
    return "";
}

// Synthesize a start timestamp for entries logged outside the app:
// the spent_on date at 09:00.
std::time_t synthStart(const std::string &spent_on) {
    int tzd = 0;
    Poco::DateTime dt;
    if (Poco::DateTimeParser::tryParse("%Y-%m-%d", spent_on, dt, tzd)) {
        dt.assign(dt.year(), dt.month(), dt.day(), 9, 0, 0);
        return dt.timestamp().epochTime();
    }
    return Poco::Timestamp().epochTime();
}

// Map one Redmine issue JSON object to a Toggl-shaped "task". When forceActive
// is true (live search) the task is marked active regardless of the issue's
// real status: the autocomplete builder hides inactive tasks, so without this a
// searched-for closed (or foreign) issue would be fetched but never shown.
Json::Value mapIssueToTask(const Json::Value &ri, bool forceActive) {
    Json::Value t;
    Poco::UInt64 issueID = ri["id"].asUInt64();
    t["id"] = Json::UInt64(issueID);
    std::stringstream name;
    name << "#" << issueID << ": " << ri["subject"].asString();
    t["name"] = name.str();
    t["pid"] = Json::UInt64(ri["project"]["id"].asUInt64());
    t["wid"] = Json::UInt64(kSyntheticWorkspaceID);
    bool closed = ri.isMember("status") && ri["status"].isMember("is_closed")
        && ri["status"]["is_closed"].asBool();
    t["active"] = forceActive ? true : !closed;
    return t;
}

// Case-insensitive ASCII string compare.
bool iequals(const std::string &a, const std::string &b) {
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); ++i) {
        if (std::tolower(static_cast<unsigned char>(a[i])) !=
                std::tolower(static_cast<unsigned char>(b[i]))) {
            return false;
        }
    }
    return true;
}

// Match the toggl_start/stop/guid custom fields by name in a JSON array of
// {id, name, [customized_type]} objects (either /custom_fields.json defs or a
// time entry's custom_fields), updating the RedmineClient ids and found flags.
// Skips non-time_entry defs when customized_type is present.
void matchCustomFields(const Json::Value &fields,
                       bool *fStart, bool *fStop, bool *fGuid) {
    for (unsigned int i = 0; i < fields.size(); i++) {
        const Json::Value &f = fields[i];
        if (f.isMember("customized_type") &&
                f["customized_type"].asString() != "time_entry") {
            continue;
        }
        if (!f.isMember("name") || !f.isMember("id")) continue;
        int id = f["id"].asInt();
        if (id <= 0) continue;
        const std::string name = f["name"].asString();
        if (name == "toggl_start") {
            RedmineClient::kCustomFieldStart = id; *fStart = true;
        } else if (name == "toggl_stop") {
            RedmineClient::kCustomFieldStop = id; *fStop = true;
        } else if (name == "toggl_guid") {
            RedmineClient::kCustomFieldGUID = id; *fGuid = true;
        }
    }
}

}  // namespace

void RedmineClient::ResolveSchema(const std::string &apiKey,
                                  const Json::Value &timeEntries) {
    // Activity: prefer one named "Development"; else the instance default; else
    // the first active. Leaves the fallback id untouched on failure.
    Json::Value acts;
    if (redmineGet(apiKey, "/enumerations/time_entry_activities.json", &acts)
            == noError) {
        const Json::Value &arr = acts["time_entry_activities"];
        int byName = 0, byDefault = 0, firstActive = 0;
        for (unsigned int i = 0; i < arr.size(); i++) {
            const Json::Value &a = arr[i];
            int id = a["id"].asInt();
            if (id <= 0) continue;
            bool active = !a.isMember("active") || a["active"].asBool();
            if (byName == 0 && iequals(a["name"].asString(), "Development")) {
                byName = id;
            }
            if (byDefault == 0 && a["is_default"].asBool()) byDefault = id;
            if (firstActive == 0 && active) firstActive = id;
        }
        int chosen = byName ? byName : (byDefault ? byDefault : firstActive);
        if (chosen) kDefaultActivityID = chosen;
    }

    // Custom-field ids by name. The user's own time entries carry {id,name} and
    // are readable by anyone; only if a field is still unresolved do we try the
    // admin-only /custom_fields.json.
    bool fStart = false, fStop = false, fGuid = false;
    for (unsigned int i = 0; i < timeEntries.size(); i++) {
        matchCustomFields(timeEntries[i]["custom_fields"],
                          &fStart, &fStop, &fGuid);
    }
    if (!(fStart && fStop && fGuid)) {
        Json::Value cfs;
        if (redmineGet(apiKey, "/custom_fields.json", &cfs) == noError) {
            matchCustomFields(cfs["custom_fields"], &fStart, &fStop, &fGuid);
        }
    }
}

error RedmineClient::FetchAccountJSON(
    const std::string &apiKey,
    const Poco::Int64 since,
    std::string *out_json) {

    // --- current user ---
    Json::Value userRoot;
    error err = redmineGet(apiKey, "/users/current.json", &userRoot);
    if (err != noError) {
        return err;
    }
    const Json::Value &ru = userRoot["user"];
    if (!ru["id"].asUInt64()) {
        return error("Redmine: /users/current returned no user id");
    }

    // --- projects ---
    Json::Value rprojects(Json::arrayValue);
    err = redmineGetPaged(apiKey, "/projects.json", "", "projects", &rprojects, 0);
    if (err != noError) {
        return err;
    }

    // --- my open issues (the cached/offline set; live search covers the rest) ---
    Json::Value rissues(Json::arrayValue);
    err = redmineGetPaged(apiKey, "/issues.json",
                          "assigned_to_id=me&status_id=open&sort=updated_on:desc",
                          "issues", &rissues, kMaxCachedIssues);
    if (err != noError) {
        return err;
    }

    // --- my recent time entries ---
    Poco::LocalDateTime now;
    Poco::LocalDateTime fromDate =
        now - Poco::Timespan(kTimeEntryWindowDays, 0, 0, 0, 0);
    std::string fromStr = Poco::DateTimeFormatter::format(fromDate, "%Y-%m-%d");
    std::stringstream teQuery;
    teQuery << "user_id=me&from=" << fromStr;
    Json::Value rtimeentries(Json::arrayValue);
    err = redmineGetPaged(apiKey, "/time_entries.json",
                          teQuery.str(), "time_entries", &rtimeentries, 0);
    if (err != noError) {
        return err;
    }

    // Resolve the instance-specific activity + custom-field ids by name before
    // they're used below (read-back) and later by the write path. Pass the
    // entries just fetched so non-admins can learn ids from their own data.
    ResolveSchema(apiKey, rtimeentries);

    // ---- assemble the Toggl-shaped account document ----
    Json::Value data;
    data["id"] = Json::UInt64(ru["id"].asUInt64());
    data["default_wid"] = Json::UInt64(kSyntheticWorkspaceID);
    data["api_token"] = apiKey;
    data["email"] = ru["mail"].asString();
    {
        std::string fullname = ru["firstname"].asString();
        if (!ru["lastname"].asString().empty()) {
            if (!fullname.empty()) fullname += " ";
            fullname += ru["lastname"].asString();
        }
        if (fullname.empty()) fullname = ru["login"].asString();
        data["fullname"] = fullname;
    }

    // synthetic workspace (Redmine has none)
    Json::Value workspaces(Json::arrayValue);
    {
        Json::Value ws;
        ws["id"] = Json::UInt64(kSyntheticWorkspaceID);
        ws["name"] = "Redmine";
        ws["admin"] = true;
        ws["premium"] = false;
        workspaces.append(ws);
    }
    data["workspaces"] = workspaces;
    data["clients"] = Json::Value(Json::arrayValue);
    data["tags"] = Json::Value(Json::arrayValue);

    // projects
    static const char *kPalette[] = {
        "#0b83d9", "#9e5bd9", "#d94182", "#e36a00", "#bf7000",
        "#2da608", "#06a893", "#c9806b", "#465bb3", "#990099"
    };
    Json::Value projects(Json::arrayValue);
    for (unsigned int i = 0; i < rprojects.size(); i++) {
        const Json::Value &rp = rprojects[i];
        Json::Value p;
        p["id"] = Json::UInt64(rp["id"].asUInt64());
        p["name"] = rp["name"].asString();
        p["wid"] = Json::UInt64(kSyntheticWorkspaceID);
        p["active"] = (rp["status"].asInt() == 1);
        p["color"] = kPalette[rp["id"].asUInt64() % 10];
        projects.append(p);
    }
    data["projects"] = projects;

    // tasks (Redmine issues) — keep the real open/closed state for the cached set
    Json::Value tasks(Json::arrayValue);
    for (unsigned int i = 0; i < rissues.size(); i++) {
        tasks.append(mapIssueToTask(rissues[i], false));
    }
    data["tasks"] = tasks;

    // time entries
    Json::Value timeentries(Json::arrayValue);
    for (unsigned int i = 0; i < rtimeentries.size(); i++) {
        const Json::Value &rt = rtimeentries[i];
        Json::Value te;
        te["id"] = Json::UInt64(rt["id"].asUInt64());
        te["wid"] = Json::UInt64(kSyntheticWorkspaceID);
        if (rt.isMember("project")) {
            te["pid"] = Json::UInt64(rt["project"]["id"].asUInt64());
        }
        if (rt.isMember("issue")) {
            te["tid"] = Json::UInt64(rt["issue"]["id"].asUInt64());
        }
        te["description"] =
            rt["comments"].isString() ? rt["comments"].asString() : "";
        te["billable"] = false;
        te["duronly"] = false;

        std::string startStr = customField(rt, kCustomFieldStart);
        std::string stopStr = customField(rt, kCustomFieldStop);
        std::string guid = customField(rt, kCustomFieldGUID);

        std::time_t startTs = 0;
        std::time_t stopTs = 0;
        if (!startStr.empty() && !stopStr.empty()) {
            startTs = Formatter::Parse8601(startStr);
            stopTs = Formatter::Parse8601(stopStr);
        }
        if (startTs <= 0 || stopTs <= startTs) {
            // Entry logged in the Redmine web UI: synthesize from spent_on+hours.
            startTs = synthStart(rt["spent_on"].asString());
            double hours = rt["hours"].asDouble();
            std::time_t dur = static_cast<std::time_t>(hours * 3600.0 + 0.5);
            if (dur < 1) dur = 1;
            stopTs = startTs + dur;
        }
        te["start"] = Formatter::Format8601(startTs);
        te["stop"] = Formatter::Format8601(stopTs);
        te["duration"] =
            Json::Int64(static_cast<Poco::Int64>(stopTs - startTs));
        if (!guid.empty()) {
            te["guid"] = guid;
        }
        if (rt.isMember("updated_on")) {
            te["at"] = rt["updated_on"].asString();
        }
        timeentries.append(te);
    }
    data["time_entries"] = timeentries;

    Json::Value root;
    root["since"] = Json::Int64(Poco::Timestamp().epochTime());
    root["data"] = data;

    Json::StreamWriterBuilder wb;
    wb["indentation"] = "";
    *out_json = Json::writeString(wb, root);

    (void)since;  // full-window fetch for now; incremental can use this later.
    return noError;
}

error RedmineClient::SearchIssuesJSON(
    const std::string &apiKey,
    const std::string &query,
    Json::Value *out_tasks) {

    *out_tasks = Json::Value(Json::arrayValue);
    if (query.empty()) {
        return noError;
    }

    // All-digits → look up by issue id; otherwise match the subject substring.
    bool allDigits =
        query.find_first_not_of("0123456789") == std::string::npos;

    std::stringstream q;
    if (allDigits) {
        q << "issue_id=" << query;
    } else {
        // Passed verbatim: https_client URL-encodes the whole relative URL, so
        // pre-encoding here would double-encode. status_id=* spans all statuses.
        q << "subject=~" << query;
    }
    q << "&status_id=*";

    Json::Value rissues(Json::arrayValue);
    error err = redmineGetPaged(apiKey, "/issues.json", q.str(),
                                "issues", &rissues, kMaxSearchResults);
    if (err != noError) {
        return err;
    }
    for (unsigned int i = 0; i < rissues.size(); i++) {
        out_tasks->append(mapIssueToTask(rissues[i], /*forceActive=*/true));
    }
    return noError;
}

}  // namespace toggl

// Copyright 2026 Toggl Desktop -> Redmine fork

#include "redmine_client.h"

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

const int RedmineClient::kCustomFieldStart = 6;  // toggl_start
const int RedmineClient::kCustomFieldStop = 7;   // toggl_stop
const int RedmineClient::kCustomFieldGUID = 8;   // toggl_guid

static const Poco::UInt64 kSyntheticWorkspaceID = 1;
static const int kPageSize = 100;
// Match the app's ~30-day local time-entry retention.
static const int kTimeEntryWindowDays = 30;
// Cap the locally-cached issue set (a single dev can have thousands of open
// issues); the most-recently-updated ones are cached for offline/quick pick and
// live search (toggl_search_issues) reaches the rest.
static const int kMaxCachedIssues = 500;

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

}  // namespace

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

    // tasks (Redmine issues)
    Json::Value tasks(Json::arrayValue);
    for (unsigned int i = 0; i < rissues.size(); i++) {
        const Json::Value &ri = rissues[i];
        Json::Value t;
        Poco::UInt64 issueID = ri["id"].asUInt64();
        t["id"] = Json::UInt64(issueID);
        std::stringstream name;
        name << "#" << issueID << ": " << ri["subject"].asString();
        t["name"] = name.str();
        t["pid"] = Json::UInt64(ri["project"]["id"].asUInt64());
        t["wid"] = Json::UInt64(kSyntheticWorkspaceID);
        t["active"] = !ri["status"]["is_closed"].asBool();
        tasks.append(t);
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

}  // namespace toggl

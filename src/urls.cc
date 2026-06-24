// Copyright 2015 Toggl Desktop developers

#include "urls.h"

#include <cstdlib>

namespace toggl {

namespace urls {

// Base URL of the Redmine backend. Configured at runtime (login screen /
// settings) via SetBaseURL(). Never hardcoded to an internal host; for headless
// testing it falls back to the TOGGL_REDMINE_URL environment variable.
static std::string base_url_;

// Retained for source compatibility with existing callers; no longer affects
// which backend is used now that the base URL is configurable.
#ifndef TOGGL_PRODUCTION_BUILD
static bool use_staging_as_backend = true;
#else
static bool use_staging_as_backend = false;
#endif

// Whether requests are allowed to the backend
static bool im_a_teapot_ = false;

// Whether requests are allowed at all (like in tests)
static bool requests_allowed_ = true;

void SetUseStagingAsBackend(const bool value) {
    use_staging_as_backend = value;
}

bool IsUsingStagingAsBackend() {
    return use_staging_as_backend;
}

void SetBaseURL(const std::string &value) {
    base_url_ = value;
    // Normalize: drop trailing slashes so paths join cleanly.
    while (!base_url_.empty() && base_url_.back() == '/') {
        base_url_.pop_back();
    }
}

std::string BaseURL() {
    if (!base_url_.empty()) {
        return base_url_;
    }
    const char *env = std::getenv("TOGGL_REDMINE_URL");
    if (env && *env) {
        return std::string(env);
    }
    return base_url_;  // empty until configured at runtime
}

// All backend endpoints resolve to the single configurable Redmine base.
// (Redmine has no separate desktop/sync/websocket hosts.)
std::string Main() {
    return BaseURL();
}

std::string API() {
    return BaseURL();
}

std::string SyncAPI() {
    return BaseURL();
}

std::string TimelineUpload() {
    return BaseURL();
}

std::string WebSocket() {
    return BaseURL();
}

bool ImATeapot() {
    return im_a_teapot_;
}

void SetImATeapot(const bool value) {
    im_a_teapot_ = value;
}

bool RequestsAllowed() {
    return requests_allowed_;
}

void SetRequestsAllowed(const bool value) {
    requests_allowed_ = value;
}


}  // namespace urls

}  // namespace toggl

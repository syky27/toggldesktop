# Builds the existing C++ core (src/) as a standalone shared library for the
# Flutter app — decoupled from the Qt-coupled root CMake. This is the FP-10
# deliverable and is reused by each Flutter desktop embedder build (FP-60).
#
#   cmake -S app/native -B build/native -DCMAKE_BUILD_TYPE=Release
#   cmake --build build/native -j
#
# Produces libTogglDesktopLibrary.so / .dylib / TogglDesktopLibrary.dll.
cmake_minimum_required(VERSION 3.16)
project(TogglDesktopCore CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Path to the repo's core sources (this file lives in app/native/).
get_filename_component(CORE_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../src" ABSOLUTE)

find_package(Poco CONFIG REQUIRED COMPONENTS Crypto DataSQLite NetSSL Foundation Util Net)

include(FindPkgConfig)
pkg_check_modules(JSONCPP REQUIRED jsoncpp)

set(CORE_SOURCES
    util/custom_error_handler.cc
    util/formatter.cc
    util/logger.cc
    util/random.cc
    util/rectangle.cc
    util/json.cc
    database/database.cc
    database/migrations.cc
    model/alpha_features.cpp
    model/autotracker.cc
    model/base_model.cc
    model_change.cc
    model/client.cc
    model/project.cc
    model/settings.cc
    model/tag.cc
    model/task.cc
    model/time_entry.cc
    model/timeline_event.cc
    model/user.cc
    model/workspace.cc
    analytics.cc
    context.cc
    error.cc
    gui.cc
    help_article.cc
    https_client.cc
    idle.cc
    netconf.cc
    platforminfo.cc
    proxy.cc
    related_data.cc
    timeline_uploader.cc
    toggl_api.cc
    toggl_api_private.cc
    urls.cc
    redmine_client.cc
    websocket_client.cc
    window_change_recorder.cc
    color_convert.cc
    onboarding_service.cpp
)

if(ANDROID)
    list(APPEND CORE_SOURCES get_focused_window_linux.cc)
elseif(WIN32)
    list(APPEND CORE_SOURCES get_focused_window_windows.cc)
    set(PLATFORM_LIBS Winhttp Psapi)
elseif(APPLE)
    list(APPEND CORE_SOURCES get_focused_window_mac.cc)
    set(PLATFORM_LIBS "-framework Foundation" "-framework CFNetwork" "-framework AppKit")
else() # Linux desktop
    list(APPEND CORE_SOURCES get_focused_window_linux.cc)
endif()

list(TRANSFORM CORE_SOURCES PREPEND "${CORE_SRC}/")

add_library(TogglDesktopLibrary SHARED ${CORE_SOURCES})

target_include_directories(TogglDesktopLibrary PRIVATE
    ${CORE_SRC}
    ${JSONCPP_INCLUDE_DIRS}
)

target_compile_definitions(TogglDesktopLibrary PRIVATE
    TOGGLDESKTOP_DLL_BUILD
    APP_ENVIRONMENT="development"
    TOGGL_BUILD_TYPE="manual"
    TOGGL_SYNC_FORCE_LEGACY
)

target_link_libraries(TogglDesktopLibrary PRIVATE
    Poco::Crypto Poco::DataSQLite Poco::NetSSL Poco::Foundation Poco::Util Poco::Net
    ${JSONCPP_LIBRARIES}
    ${PLATFORM_LIBS}
)

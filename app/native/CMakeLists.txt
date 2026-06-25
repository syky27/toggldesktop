# Builds the existing C++ core (src/) as a standalone shared library for the
# Flutter app — decoupled from the Qt-coupled root CMake. This is the FP-10
# deliverable and is reused by each Flutter desktop embedder build (FP-60).
#
#   cmake -S app/native -B build/native -DCMAKE_BUILD_TYPE=Release
#   cmake --build build/native -j
#
# Produces libTogglDesktopLibrary.so / .dylib / TogglDesktopLibrary.dll.
cmake_minimum_required(VERSION 3.16)
project(TogglDesktopCore CXX C)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)

# Path to the repo's core sources (this file lives in app/native/).
get_filename_component(CORE_SRC "${CMAKE_CURRENT_SOURCE_DIR}/../../src" ABSOLUTE)

# Dependency discovery.
#  * Desktop (Linux/macOS/Windows): system packages (apt/brew/vcpkg) via
#    find_package + pkg-config.
#  * Android: there are no system packages — point CMake at a prefix that holds
#    the cross-built OpenSSL/Poco/jsoncpp for the current ABI. Produce it with
#    app/native/android/build-deps.sh and pass -DREDTICK_DEPS_PREFIX=<prefix>
#    (the Gradle externalNativeBuild does this automatically per ABI).
# REDTICK_DEPS_ROOT points at a parent dir holding one prefix per ABI
# (e.g. .deps-prefix/arm64-v8a); the per-ABI prefix is selected here. Gradle
# passes REDTICK_DEPS_ROOT so a single argument works for all ABIs.
if(ANDROID AND DEFINED REDTICK_DEPS_ROOT AND NOT DEFINED REDTICK_DEPS_PREFIX)
    set(REDTICK_DEPS_PREFIX "${REDTICK_DEPS_ROOT}/${ANDROID_ABI}")
endif()
if(DEFINED REDTICK_DEPS_PREFIX)
    list(PREPEND CMAKE_PREFIX_PATH "${REDTICK_DEPS_PREFIX}")
    list(PREPEND CMAKE_FIND_ROOT_PATH "${REDTICK_DEPS_PREFIX}")
    set(OPENSSL_ROOT_DIR "${REDTICK_DEPS_PREFIX}")
endif()

find_package(Poco CONFIG REQUIRED COMPONENTS Crypto DataSQLite NetSSL Foundation Util Net)

# jsoncpp: prefer its CMake config (used by the Android prefix); fall back to
# pkg-config on desktop.
find_package(jsoncpp CONFIG QUIET)
if(jsoncpp_FOUND)
    if(TARGET jsoncpp_static)
        set(JSONCPP_LIBRARIES jsoncpp_static)
    else()
        set(JSONCPP_LIBRARIES jsoncpp_lib)
    endif()
    set(JSONCPP_INCLUDE_DIRS "")
else()
    include(FindPkgConfig)
    pkg_check_modules(JSONCPP REQUIRED jsoncpp)
endif()

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

# Window-detection / platform-frameworks selection. Mobile (Android, iOS) uses a
# no-op stub because sandboxing forbids inspecting other apps' windows.
set(USE_WINDOW_STUB OFF)
if(ANDROID)
    set(USE_WINDOW_STUB ON)
elseif(WIN32)
    list(APPEND CORE_SOURCES get_focused_window_windows.cc)
    set(PLATFORM_LIBS Winhttp Psapi)
elseif(APPLE)
    if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
        # iOS: no AppKit; use the stub. Foundation/CFNetwork only.
        set(USE_WINDOW_STUB ON)
        set(PLATFORM_LIBS "-framework Foundation" "-framework CFNetwork")
    else() # macOS desktop
        list(APPEND CORE_SOURCES get_focused_window_mac.cc)
        set(PLATFORM_LIBS "-framework Foundation" "-framework CFNetwork" "-framework AppKit")
    endif()
else() # Linux desktop
    list(APPEND CORE_SOURCES get_focused_window_linux.cc)
endif()

list(TRANSFORM CORE_SOURCES PREPEND "${CORE_SRC}/")

# FFI bridge shim (FP-22b): deep-copies view structs for thread-safe Dart
# delivery. Compiled into the same library so rt_* symbols ship alongside toggl_*.
list(APPEND CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/bridge.c")

# Mobile window-detection stub (absolute path, added after the prepend).
if(USE_WINDOW_STUB)
    list(APPEND CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/get_focused_window_stub.cc")
endif()

# iOS links the core statically into the Runner (DynamicLibrary.process); all
# other platforms load a shared library (DynamicLibrary.open).
if(CMAKE_SYSTEM_NAME STREQUAL "iOS")
    add_library(TogglDesktopLibrary STATIC ${CORE_SOURCES})
else()
    add_library(TogglDesktopLibrary SHARED ${CORE_SOURCES})
endif()

target_include_directories(TogglDesktopLibrary PRIVATE
    ${CORE_SRC}
    ${CMAKE_CURRENT_SOURCE_DIR}
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

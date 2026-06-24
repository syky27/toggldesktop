// Redtick FFI bridge shim (FP-22b).
//
// The core invokes its TogglDisplay* callbacks synchronously on its own threads
// and frees the TogglTimeEntryView linked list as soon as the callback returns.
// Dart's NativeCallable.listener runs LATER on the isolate event loop, by which
// time that memory is gone. This shim runs on the core thread, DEEP-COPIES the
// view data into heap-owned, pointer-flat structs, and forwards the owned
// pointer to a Dart listener. Dart reads it and calls rt_free_* to release it.
//
// All strings are heap-duplicated (UTF-8) and owned by the returned struct.
#ifndef REDTICK_BRIDGE_H_
#define REDTICK_BRIDGE_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#ifdef _WIN32
#define RT_EXPORT __declspec(dllexport)
#else
#define RT_EXPORT
#endif

// Flat, owned mirror of TogglTimeEntryView (subset the app consumes).
typedef struct {
    uint64_t ID;
    int64_t DurationInSeconds;
    char *Description;
    char *Duration;
    char *ProjectLabel;
    char *TaskLabel;
    char *ClientLabel;
    char *Color;
    char *GUID;
    char *Tags;
    int Billable;
    uint64_t ActivityID;
    uint64_t Started;
    uint64_t Ended;
    char *StartTimeString;
    char *EndTimeString;
    int IsHeader;
    char *DateHeader;
    char *DateDuration;
    int Unsynced;
    char *Error;
} RtTimeEntry;

typedef struct {
    int64_t count;
    int show_load_more;
    RtTimeEntry *items; // array of `count` items
} RtTimeEntryList;

typedef void (*RtTimeEntryListCb)(RtTimeEntryList *owned);
typedef void (*RtTimerStateCb)(RtTimeEntry *owned_or_null);

// Register Dart listeners. These internally register the matching core
// callbacks (toggl_on_time_entry_list / toggl_on_timer_state), so calling them
// satisfies Context::VerifyCallbacks.
RT_EXPORT void rt_on_time_entry_list(void *ctx, RtTimeEntryListCb cb);
RT_EXPORT void rt_on_timer_state(void *ctx, RtTimerStateCb cb);

// Free owned payloads handed to the Dart listeners.
RT_EXPORT void rt_free_time_entry_list(RtTimeEntryList *list);
RT_EXPORT void rt_free_time_entry(RtTimeEntry *te);

#ifdef __cplusplus
}
#endif

#endif // REDTICK_BRIDGE_H_

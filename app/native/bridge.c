// Redtick FFI bridge shim implementation (FP-22b). See bridge.h.
#include "bridge.h"

#include <stdlib.h>
#include <string.h>

#include "toggl_api.h"

// Single-context app: store the Dart listener pointers in globals.
static RtTimeEntryListCb g_list_cb = NULL;
static RtTimerStateCb g_timer_cb = NULL;

static char *rt_strdup(const char *s) {
    if (!s) return NULL;
    size_t n = strlen(s) + 1;
    char *p = (char *)malloc(n);
    if (p) memcpy(p, s, n);
    return p;
}

static void rt_copy_one(RtTimeEntry *dst, const TogglTimeEntryView *v) {
    dst->ID = v->ID;
    dst->DurationInSeconds = v->DurationInSeconds;
    dst->Description = rt_strdup(v->Description);
    dst->Duration = rt_strdup(v->Duration);
    dst->ProjectLabel = rt_strdup(v->ProjectLabel);
    dst->TaskLabel = rt_strdup(v->TaskLabel);
    dst->ClientLabel = rt_strdup(v->ClientLabel);
    dst->Color = rt_strdup(v->Color);
    dst->GUID = rt_strdup(v->GUID);
    dst->Tags = rt_strdup(v->Tags);
    dst->Billable = v->Billable;
    dst->ActivityID = v->ActivityID;
    dst->Started = v->Started;
    dst->Ended = v->Ended;
    dst->StartTimeString = rt_strdup(v->StartTimeString);
    dst->EndTimeString = rt_strdup(v->EndTimeString);
    dst->IsHeader = v->IsHeader;
    dst->DateHeader = rt_strdup(v->DateHeader);
    dst->DateDuration = rt_strdup(v->DateDuration);
    dst->Unsynced = v->Unsynced;
    dst->Error = rt_strdup(v->Error);
}

static void rt_free_fields(RtTimeEntry *t) {
    free(t->Description);
    free(t->Duration);
    free(t->ProjectLabel);
    free(t->TaskLabel);
    free(t->ClientLabel);
    free(t->Color);
    free(t->GUID);
    free(t->Tags);
    free(t->StartTimeString);
    free(t->EndTimeString);
    free(t->DateHeader);
    free(t->DateDuration);
    free(t->Error);
}

// Runs synchronously on the core thread.
static void on_time_entry_list(const bool_t open,
                               TogglTimeEntryView *first,
                               const bool_t show_load_more) {
    (void)open;
    if (!g_list_cb) return;

    int64_t count = 0;
    for (TogglTimeEntryView *n = first; n; n = (TogglTimeEntryView *)n->Next) {
        count++;
    }

    RtTimeEntryList *list = (RtTimeEntryList *)malloc(sizeof(RtTimeEntryList));
    list->count = count;
    list->show_load_more = show_load_more;
    list->items = count > 0
        ? (RtTimeEntry *)calloc((size_t)count, sizeof(RtTimeEntry))
        : NULL;

    int64_t i = 0;
    for (TogglTimeEntryView *n = first; n; n = (TogglTimeEntryView *)n->Next) {
        rt_copy_one(&list->items[i++], n);
    }

    // Hands the owned pointer to the Dart listener (enqueues; returns at once).
    g_list_cb(list);
}

static void on_timer_state(TogglTimeEntryView *te) {
    if (!g_timer_cb) return;
    if (!te) {
        g_timer_cb(NULL);
        return;
    }
    RtTimeEntry *one = (RtTimeEntry *)calloc(1, sizeof(RtTimeEntry));
    rt_copy_one(one, te);
    g_timer_cb(one);
}

void rt_on_time_entry_list(void *ctx, RtTimeEntryListCb cb) {
    g_list_cb = cb;
    toggl_on_time_entry_list(ctx, on_time_entry_list);
}

void rt_on_timer_state(void *ctx, RtTimerStateCb cb) {
    g_timer_cb = cb;
    toggl_on_timer_state(ctx, on_timer_state);
}

void rt_free_time_entry_list(RtTimeEntryList *list) {
    if (!list) return;
    for (int64_t i = 0; i < list->count; i++) {
        rt_free_fields(&list->items[i]);
    }
    free(list->items);
    free(list);
}

void rt_free_time_entry(RtTimeEntry *te) {
    if (!te) return;
    rt_free_fields(te);
    free(te);
}

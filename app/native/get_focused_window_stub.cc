// Android & iOS stub for the desktop-only focused-window detection used by the
// autotracker / timeline. Mobile sandboxing forbids inspecting other apps'
// windows, so this is a no-op that reports "no window" (FP-11 / FP-12 / FP-53).
#include "get_focused_window.h"

int getFocusedWindowInfo(
    std::string *title,
    std::string *filename,
    bool *idle) {
    if (title) title->clear();
    if (filename) filename->clear();
    if (idle) *idle = false;
    return 1; // non-zero: no focused-window info available on mobile
}

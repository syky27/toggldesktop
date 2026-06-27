#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gio/gio.h>
#include <string.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#include <X11/extensions/scrnsaver.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* idle_channel;
  FlMethodChannel* window_channel;  // redtick/window: bring-to-front on idle.
  GtkWindow* window;                // weak ref to the toplevel for raising.
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Idle detection (design §3.9): report seconds since the last user input so
// Dart can prompt to keep/discard idle time while a timer runs. Linux has no
// single idle API, so we pick by display server:
//   * GNOME (X11 or Wayland) -> org.gnome.Mutter.IdleMonitor.GetIdletime (D-Bus)
//   * any other X11 desktop  -> XScreenSaverQueryInfo (desktop-agnostic)
//   * other Wayland sessions -> unsupported (returns 0; the prompt never fires)

// Sets *out_seconds from GNOME's Mutter idle monitor. Returns FALSE when Mutter
// is absent (non-GNOME) so the caller can fall back to X11.
static gboolean idle_seconds_from_mutter(double* out_seconds) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GDBusConnection) bus =
      g_bus_get_sync(G_BUS_TYPE_SESSION, nullptr, &error);
  if (bus == nullptr) {
    return FALSE;
  }
  g_autoptr(GVariant) reply = g_dbus_connection_call_sync(
      bus, "org.gnome.Mutter.IdleMonitor", "/org/gnome/Mutter/IdleMonitor/Core",
      "org.gnome.Mutter.IdleMonitor", "GetIdletime", nullptr,
      G_VARIANT_TYPE("(t)"), G_DBUS_CALL_FLAGS_NONE, 500, nullptr, &error);
  if (reply == nullptr) {
    return FALSE;  // not GNOME: ServiceUnknown returns fast, no hang.
  }
  guint64 idle_ms = 0;
  g_variant_get(reply, "(t)", &idle_ms);
  *out_seconds = idle_ms / 1000.0;
  return TRUE;
}

#ifdef GDK_WINDOWING_X11
// Sets *out_seconds from the X screen-saver idle counter. Returns FALSE off X11
// (the WAYLAND_DISPLAY guard avoids XWayland, whose counter is bogus under a
// Wayland compositor).
static gboolean idle_seconds_from_x11(double* out_seconds) {
  if (g_getenv("WAYLAND_DISPLAY") != nullptr) {
    return FALSE;
  }
  Display* display = XOpenDisplay(nullptr);
  if (display == nullptr) {
    return FALSE;
  }
  gboolean ok = FALSE;
  int event_base = 0;
  int error_base = 0;
  if (XScreenSaverQueryExtension(display, &event_base, &error_base)) {
    XScreenSaverInfo* info = XScreenSaverAllocInfo();
    if (info != nullptr &&
        XScreenSaverQueryInfo(display, DefaultRootWindow(display), info)) {
      *out_seconds = info->idle / 1000.0;
      ok = TRUE;
    }
    if (info != nullptr) {
      XFree(info);
    }
  }
  XCloseDisplay(display);
  return ok;
}
#endif

// Handles the `redtick/idle` channel's `idleSeconds` method.
static void idle_method_call_cb(FlMethodChannel* channel,
                                FlMethodCall* method_call, gpointer user_data) {
  (void)channel;
  (void)user_data;
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(method_call), "idleSeconds") == 0) {
    double seconds = 0.0;
    if (!idle_seconds_from_mutter(&seconds)) {
#ifdef GDK_WINDOWING_X11
      idle_seconds_from_x11(&seconds);
#endif
    }
    g_autoptr(FlValue) result = fl_value_new_float(seconds);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond to idleSeconds: %s", error->message);
  }
}

// Handles the `redtick/window` channel's `foreground` method: raise our own
// toplevel so the idle prompt is visible when the user returns. Mirrors
// idle_method_call_cb.
static void window_method_call_cb(FlMethodChannel* channel,
                                  FlMethodCall* method_call, gpointer user_data) {
  (void)channel;
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(method_call), "foreground") == 0) {
    gboolean ok = FALSE;
    if (self->window != nullptr) {
      gtk_window_deiconify(self->window);
      // No input-event timestamp here (called from a Dart timer), so use
      // gtk_window_present(), not present_with_time(): a fabricated stamp can
      // make some window managers flag "demands attention" instead of raising.
      gtk_window_present(self->window);
      ok = TRUE;
    }
    g_autoptr(FlValue) result = fl_value_new_bool(ok);
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(result));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond to foreground: %s", error->message);
  }
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;  // weak ref for redtick/window bring-to-front.

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Redtick");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Redtick");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  // Idle detection channel (design §3.9); see idle_method_call_cb above. Keep a
  // ref on self so the channel outlives this scope and its handler stays live.
  g_autoptr(FlStandardMethodCodec) idle_codec = fl_standard_method_codec_new();
  self->idle_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)), "redtick/idle",
      FL_METHOD_CODEC(idle_codec));
  fl_method_channel_set_method_call_handler(self->idle_channel,
                                            idle_method_call_cb, self, nullptr);

  // Window control channel (redtick/window); see window_method_call_cb above.
  g_autoptr(FlStandardMethodCodec) window_codec = fl_standard_method_codec_new();
  self->window_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "redtick/window", FL_METHOD_CODEC(window_codec));
  fl_method_channel_set_method_call_handler(
      self->window_channel, window_method_call_cb, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_object(&self->idle_channel);
  g_clear_object(&self->window_channel);
  self->window = nullptr;  // non-owning: just drop the reference.
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}

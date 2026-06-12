#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include <cstdio>
#include <cstring>
#include <cstdlib>

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

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
    gtk_header_bar_set_title(header_bar, "wasla");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "wasla");
  }

  gtk_window_set_default_size(window, 1280, 720);

  // Set the Linux Window Icon
  g_autoptr(GError) error = nullptr;
  g_autofree gchar *exe_path = g_file_read_link("/proc/self/exe", nullptr);
  g_autofree gchar *exe_dir = g_path_get_dirname(exe_path);
  g_autofree gchar *icon_path = g_build_filename(exe_dir, "data", "flutter_assets", "assets", "images", "Wasla-logo.png", nullptr);
  
  g_autoptr(GdkPixbuf) icon = gdk_pixbuf_new_from_file(icon_path, &error);
  if (icon != nullptr) {
    gtk_window_set_icon(window, icon);
  } else {
    g_warning("Failed to load window icon: %s", error->message);
  }

  gtk_widget_show(GTK_WIDGET(window));

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

  gtk_widget_grab_focus(GTK_WIDGET(view));

  // Restore mic on window close (X button).
  // GTK fires delete-event instead of SIGTERM, so we intercept it here
  // and run pactl synchronously before the app quits.
  g_signal_connect(window, "delete-event",
    G_CALLBACK(+[](GtkWidget*, GdkEvent*, gpointer) -> gboolean {
      // Method 1: Direct detection — if the current default source is a
      // monitor, find a real mic and restore it immediately.
      // This handles the race condition where the recovery file hasn't
      // been written yet by the Dart VM before GTK closes.
      FILE* check = popen("pactl get-default-source 2>/dev/null", "r");
      if (check) {
        char current[256] = {0};
        if (fgets(current, sizeof(current), check)) {
          if (strstr(current, ".monitor")) {
            FILE* list = popen(
              "pactl list short sources 2>/dev/null | "
              "grep alsa_input | grep -v monitor | "
              "awk '{print $2}' | head -1", "r");
            if (list) {
              char mic[256] = {0};
              if (fgets(mic, sizeof(mic), list)) {
                size_t len = strlen(mic);
                if (len > 0 && mic[len-1] == '\n')
                  mic[len-1] = '\0';
                if (strlen(mic) > 0) {
                  char cmd[512];
                  snprintf(cmd, sizeof(cmd),
                    "pactl set-default-source %s", mic);
                  system(cmd);
                }
              }
              pclose(list);
            }
          }
        }
        pclose(check);
      }

      // Method 2: Recovery file — reads the source name saved by Dart
      // at screen-share start, as a fallback for the specific mic name.
      FILE* f = fopen("/tmp/wasla_audio_recovery.txt", "r");
      if (f) {
        char source[256] = {0};
        if (fgets(source, sizeof(source), f)) {
          size_t len = strlen(source);
          if (len > 0 && source[len-1] == '\n')
            source[len-1] = '\0';
          if (strlen(source) > 0) {
            char cmd[512];
            snprintf(cmd, sizeof(cmd),
              "pactl set-default-source %s", source);
            system(cmd);
          }
        }
        fclose(f);
        remove("/tmp/wasla_audio_recovery.txt");
      }
      // Return FALSE to allow normal close to proceed
      return FALSE;
    }), nullptr);
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

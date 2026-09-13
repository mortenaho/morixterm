#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static gboolean load_icon_pixbuf(const gchar* path, GdkPixbuf** out_pixbuf) {
  if (path == nullptr || !g_file_test(path, G_FILE_TEST_IS_REGULAR)) {
    return FALSE;
  }
  g_autoptr(GError) error = nullptr;
  GdkPixbuf* pixbuf = gdk_pixbuf_new_from_file_at_size(path, 256, 256, &error);
  if (pixbuf == nullptr) {
    g_warning("morixterm: failed to load icon %s (%s)", path,
              error != nullptr ? error->message : "unknown error");
    return FALSE;
  }
  *out_pixbuf = pixbuf;
  return TRUE;
}

// Helps GNOME/KDE taskbars map this process to a branded icon even under
// `flutter run`, where no system .desktop entry exists yet.
static void install_user_desktop_entry(const gchar* exe_path,
                                       const gchar* icon_path) {
  const gchar* home = g_get_home_dir();
  if (home == nullptr || exe_path == nullptr || icon_path == nullptr) {
    return;
  }

  g_autofree gchar* icon_dir = g_build_filename(
      home, ".local", "share", "icons", "hicolor", "256x256", "apps", nullptr);
  g_mkdir_with_parents(icon_dir, 0755);
  g_autofree gchar* icon_dst =
      g_build_filename(icon_dir, APPLICATION_ID ".png", nullptr);

  g_autofree gchar* icon_bytes = nullptr;
  gsize icon_len = 0;
  if (g_file_get_contents(icon_path, &icon_bytes, &icon_len, nullptr)) {
    g_file_set_contents(icon_dst, icon_bytes, static_cast<gssize>(icon_len),
                        nullptr);
  }

  g_autofree gchar* apps_dir =
      g_build_filename(home, ".local", "share", "applications", nullptr);
  g_mkdir_with_parents(apps_dir, 0755);
  g_autofree gchar* desktop_path =
      g_build_filename(apps_dir, APPLICATION_ID ".desktop", nullptr);
  g_autofree gchar* desktop = g_strdup_printf(
      "[Desktop Entry]\n"
      "Type=Application\n"
      "Name=morixterm\n"
      "Comment=SSH / RDP client and file transfer\n"
      "Exec=\"%s\"\n"
      "Icon=%s\n"
      "Terminal=false\n"
      "Categories=Network;RemoteAccess;\n"
      "StartupWMClass=%s\n"
      "StartupNotify=true\n"
      "NoDisplay=false\n",
      exe_path, APPLICATION_ID, APPLICATION_ID);
  g_file_set_contents(desktop_path, desktop, -1, nullptr);

  g_autoptr(GError) error = nullptr;
  g_autofree gchar* update_desktop = g_strdup_printf(
      "update-desktop-database \"%s\"", apps_dir);
  g_spawn_command_line_async(update_desktop, &error);
  g_autofree gchar* icon_theme_dir =
      g_build_filename(home, ".local", "share", "icons", "hicolor", nullptr);
  g_autofree gchar* update_icons = g_strdup_printf(
      "gtk-update-icon-cache -f -t \"%s\"", icon_theme_dir);
  g_spawn_command_line_async(update_icons, &error);
}

static void apply_window_icon(GtkWindow* window) {
  g_autoptr(GError) link_error = nullptr;
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", &link_error);
  if (exe == nullptr) {
    return;
  }
  g_autofree gchar* dir = g_path_get_dirname(exe);

  const gchar* relatives[] = {
      "morixterm.png",
      "data/flutter_assets/assets/app_icon.png",
      "data/flutter_assets/assets/logo.png",
      "data/flutter_assets/assets/morixtrem-mark.png",
      nullptr,
  };

  GdkPixbuf* pixbuf = nullptr;
  g_autofree gchar* used_path = nullptr;
  for (int i = 0; relatives[i] != nullptr; ++i) {
    g_autofree gchar* candidate =
        g_build_filename(dir, relatives[i], nullptr);
    if (load_icon_pixbuf(candidate, &pixbuf)) {
      used_path = g_steal_pointer(&candidate);
      break;
    }
  }
  if (pixbuf == nullptr) {
    return;
  }

  gtk_window_set_default_icon(pixbuf);
  gtk_window_set_icon(window, pixbuf);
  g_object_unref(pixbuf);

  if (used_path != nullptr) {
    install_user_desktop_entry(exe, used_path);
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
    gtk_header_bar_set_title(header_bar, "morixterm");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "morixterm");
  }

  gtk_window_set_default_size(window, 1280, 720);
  apply_window_icon(window);

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

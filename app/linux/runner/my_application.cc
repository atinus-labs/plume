#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "main_window.h"

// Launch flag: start with the window hidden (e.g. from XDG autostart). The
// Dart isolate still runs, so background mail sync works. Dart sees the flag
// in its entrypoint arguments too.
static constexpr char kBackgroundFlag[] = "--background";

// The only URI scheme Plume opens: `plume mailto:jane@example.org`, as run by
// the desktop entry's `Exec=plume %u` when Plume is the default mail client.
static constexpr char kMailtoScheme[] = "mailto";

// Setting this environment variable to 1 disables single-instance mode, e.g.
// to run a development build next to an installed Plume.
static constexpr char kMultiInstanceEnv[] = "PLUME_ALLOW_MULTIPLE_INSTANCES";

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;

  // TRUE if this (primary) instance was launched with --background and no
  // links to open.
  gboolean start_hidden;

  // The activation token this process was launched with, if any.
  gchar* startup_token;

  // The activation token sent by the most recent remote launch, captured in
  // before_emit and consumed by the following activate.
  gchar* activation_token;

  // The main window, created on first activation.
  PlumeMainWindow* main_window;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static gboolean has_argument(char** arguments, const gchar* flag) {
  for (char** arg = arguments; arg != nullptr && *arg != nullptr; arg++) {
    if (g_strcmp0(*arg, flag) == 0) {
      return TRUE;
    }
  }
  return FALSE;
}

static gboolean is_mailto_uri(const gchar* arg) {
  g_autofree gchar* scheme = g_uri_parse_scheme(arg);
  return scheme != nullptr && g_ascii_strcasecmp(scheme, kMailtoScheme) == 0;
}

// Creates the main window (starting Flutter) on first use. Returns TRUE if it
// was created now, in which case the launch token has been used for it.
static gboolean ensure_main_window(MyApplication* self) {
  if (self->main_window != nullptr) {
    return FALSE;
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  self->main_window =
      plume_main_window_new(GTK_APPLICATION(self), project, self->start_hidden,
                            self->startup_token);
  g_clear_pointer(&self->startup_token, g_free);
  return TRUE;
}

// Implements GApplication::activate.
//
// Runs in the primary instance: once for its own launch, and again every time
// a second instance is launched (the second instance then exits).
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  if (ensure_main_window(self)) {
    return;
  }
  g_autofree gchar* token = g_steal_pointer(&self->activation_token);
  plume_main_window_notify_activated(self->main_window, token);
  plume_main_window_present(self->main_window, token);
}

// Implements GApplication::open.
//
// Runs in the primary instance for links given on its own command line, for
// those forwarded by a second instance, and for org.freedesktop.Application
// Open calls from launchers. The links go to Dart, which opens a compose
// window for each; the main window is shown even after a --background start.
static void my_application_open(GApplication* application,
                                GFile** files,
                                gint n_files,
                                const gchar* hint) {
  MyApplication* self = MY_APPLICATION(application);

  g_autoptr(GPtrArray) uris = g_ptr_array_new_with_free_func(g_free);
  for (gint i = 0; i < n_files; i++) {
    g_autofree gchar* uri = g_file_get_uri(files[i]);
    if (uri != nullptr && is_mailto_uri(uri)) {
      g_ptr_array_add(uris, g_steal_pointer(&uri));
    } else {
      g_warning("Ignoring unsupported link: %s", uri);
    }
  }
  g_ptr_array_add(uris, nullptr);

  ensure_main_window(self);
  g_autofree gchar* token = g_steal_pointer(&self->activation_token);
  plume_main_window_open_uris(self->main_window,
                              reinterpret_cast<gchar**>(uris->pdata));
  plume_main_window_present(self->main_window, token);
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);

  // Split links to open from the flags passed to Dart, skipping the first
  // argument (the binary name).
  g_autoptr(GPtrArray) links = g_ptr_array_new_with_free_func(g_object_unref);
  GPtrArray* dart_arguments = g_ptr_array_new();
  for (gchar** arg = *arguments + 1; *arg != nullptr; arg++) {
    if (is_mailto_uri(*arg)) {
      g_ptr_array_add(links, g_file_new_for_uri(*arg));
    } else {
      g_ptr_array_add(dart_arguments, g_strdup(*arg));
    }
  }
  g_ptr_array_add(dart_arguments, nullptr);
  self->dart_entrypoint_arguments =
      reinterpret_cast<gchar**>(g_ptr_array_free(dart_arguments, FALSE));
  gboolean background = has_argument(self->dart_entrypoint_arguments,
                                     kBackgroundFlag) &&
                        links->len == 0;

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  *exit_status = 0;

  GFile** files = reinterpret_cast<GFile**>(links->pdata);
  if (g_application_get_is_remote(application)) {
    // Plume is already running. Hand it our links, or ask it to present its
    // window (forwarding our activation token via add_platform_data), and
    // exit. A background launch (autostart) has nothing to do when Plume
    // already runs.
    if (links->len > 0) {
      g_application_open(application, files, links->len, "");
    } else if (!background) {
      g_application_activate(application);
    }
    return TRUE;
  }

  // Primary instance. Keep the launcher's activation token for the first
  // present and do not leak it to child processes.
  self->start_hidden = background;
  const gchar* token = g_getenv("XDG_ACTIVATION_TOKEN");
  if (token != nullptr && g_utf8_validate(token, -1, nullptr)) {
    self->startup_token = g_strdup(token);
  }
  g_unsetenv("XDG_ACTIVATION_TOKEN");

  if (links->len > 0) {
    g_application_open(application, files, links->len, "");
  } else {
    g_application_activate(application);
  }
  return TRUE;
}

// Implements GApplication::add_platform_data.
//
// Called in a second instance when it forwards its launch to the primary.
// GTK 3 only forwards DESKTOP_STARTUP_ID (X11); also forward the Wayland
// xdg-activation token so the primary may take focus.
static void my_application_add_platform_data(GApplication* application,
                                             GVariantBuilder* builder) {
  G_APPLICATION_CLASS(my_application_parent_class)
      ->add_platform_data(application, builder);

  const gchar* token = g_getenv("XDG_ACTIVATION_TOKEN");
  if (token != nullptr && token[0] != '\0' &&
      g_utf8_validate(token, -1, nullptr)) {
    g_variant_builder_add(builder, "{sv}", "activation-token",
                          g_variant_new_string(token));
  }
}

// Implements GApplication::before_emit.
//
// Called in the primary instance before a remote activation is dispatched;
// captures the activating launch's token for my_application_activate and
// my_application_open.
static void my_application_before_emit(GApplication* application,
                                       GVariant* platform_data) {
  MyApplication* self = MY_APPLICATION(application);

  const gchar* token = nullptr;
  if (!g_variant_lookup(platform_data, "activation-token", "&s", &token)) {
    g_variant_lookup(platform_data, "desktop-startup-id", "&s", &token);
  }
  g_free(self->activation_token);
  self->activation_token =
      token != nullptr && token[0] != '\0' ? g_strdup(token) : nullptr;

  G_APPLICATION_CLASS(my_application_parent_class)
      ->before_emit(application, platform_data);
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);

  // GTK is initialised now. Set the X11 WM_CLASS class to the application ID
  // (GDK would otherwise capitalise the program name) so it matches the
  // Wayland app_id, the .desktop file and window manager rules.
  gdk_set_program_class(APPLICATION_ID);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  g_clear_object(&self->main_window);

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  g_clear_pointer(&self->startup_token, g_free);
  g_clear_pointer(&self->activation_token, g_free);
  g_clear_object(&self->main_window);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->open = my_application_open;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->add_platform_data =
      my_application_add_platform_data;
  G_APPLICATION_CLASS(klass)->before_emit = my_application_before_emit;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. GTK uses it as the Wayland app_id and the
  // X11 WM_CLASS name.
  g_set_prgname(APPLICATION_ID);

  // Single instance: a second launch activates the running instance, or
  // hands it the links it was given. HANDLES_OPEN also lets launchers and
  // other apps open links over D-Bus (org.freedesktop.Application.Open).
  GApplicationFlags flags = G_APPLICATION_HANDLES_OPEN;
  if (g_strcmp0(g_getenv(kMultiInstanceEnv), "1") == 0) {
    flags = static_cast<GApplicationFlags>(flags | G_APPLICATION_NON_UNIQUE);
  }

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     flags, nullptr));
}

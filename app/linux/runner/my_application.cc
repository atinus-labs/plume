#include "my_application.h"

#include <flutter_linux/flutter_linux.h>

#include "main_window.h"

// Launch flag: start with the window hidden (e.g. from XDG autostart). The
// Dart isolate still runs, so background mail sync works. Dart sees the flag
// in its entrypoint arguments too.
static constexpr char kBackgroundFlag[] = "--background";

// Setting this environment variable to 1 disables single-instance mode, e.g.
// to run a development build next to an installed Plume.
static constexpr char kMultiInstanceEnv[] = "PLUME_ALLOW_MULTIPLE_INSTANCES";

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;

  // TRUE if this (primary) instance was launched with --background.
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

// Implements GApplication::activate.
//
// Runs in the primary instance: once for its own launch, and again every time
// a second instance is launched (the second instance then exits).
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  if (self->main_window != nullptr) {
    g_autofree gchar* token = g_steal_pointer(&self->activation_token);
    plume_main_window_notify_activated(self->main_window, token);
    plume_main_window_present(self->main_window, token);
    return;
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  self->main_window =
      plume_main_window_new(GTK_APPLICATION(application), project,
                            self->start_hidden, self->startup_token);
  g_clear_pointer(&self->startup_token, g_free);
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);
  gboolean background = has_argument(self->dart_entrypoint_arguments,
                                     kBackgroundFlag);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  *exit_status = 0;

  if (g_application_get_is_remote(application)) {
    // Plume is already running. Ask it to present its window (forwarding our
    // activation token via add_platform_data) and exit. A background launch
    // (autostart) has nothing to do when Plume already runs.
    if (!background) {
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

  g_application_activate(application);
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
// captures the activating launch's token for my_application_activate.
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

  // Single instance: a second launch activates the running instance.
  GApplicationFlags flags = G_APPLICATION_DEFAULT_FLAGS;
  if (g_strcmp0(g_getenv(kMultiInstanceEnv), "1") == 0) {
    flags = G_APPLICATION_NON_UNIQUE;
  }

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     flags, nullptr));
}

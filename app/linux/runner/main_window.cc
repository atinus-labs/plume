#include "main_window.h"

#include <cstring>

#ifdef GDK_WINDOWING_WAYLAND
#include <gdk/gdkwayland.h>
#endif
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kWindowTitle[] = "Plume";
constexpr gint kDefaultWidth = 1280;
constexpr gint kDefaultHeight = 820;
constexpr gint kMinimumWidth = 400;
constexpr gint kMinimumHeight = 520;

// Neutral Material 3 surface colours, painted by the view until Flutter's
// first frame (and in any gap while resizing) so there is no white flash.
constexpr char kDarkBackground[] = "#141218";
constexpr char kLightBackground[] = "#fef7ff";

constexpr char kWindowChannel[] = "plume/window";

// Mapping or reconfiguring a window produces a burst of state changes within
// a few frames; they are coalesced into one notification to Dart.
constexpr guint kStateDebounceMs = 50;

// Lifecycle messages understood by the framework's SystemChannels.lifecycle.
constexpr char kLifecycleChannel[] = "flutter/lifecycle";
constexpr char kLifecycleInactive[] = "AppLifecycleState.inactive";
constexpr char kLifecycleHidden[] = "AppLifecycleState.hidden";

}  // namespace

struct _PlumeMainWindow {
  GObject parent_instance;

  // The toplevel window (we hold a reference) and the Flutter view inside it.
  GtkWindow* window;
  FlView* view;

  // The `plume/window` method channel.
  FlMethodChannel* channel;

  // TRUE until the window should be shown after the first frame. Set for
  // `--background` launches and when Dart hides the window before then.
  gboolean start_hidden;

  // TRUE once Flutter has rendered its first frame.
  gboolean have_first_frame;

  // TRUE if presenting was requested before the first frame.
  gboolean present_pending;

  // Activation token to use on the next present.
  gchar* pending_token;

  // When TRUE, the close button hides the window and notifies Dart instead
  // of quitting.
  gboolean prevent_close;

  // Copy of the most recent button press inside this window, used to start
  // interactive move/resize from Dart (needs the button, root position and
  // timestamp; on Wayland GDK uses the matching implicit-grab serial).
  GdkEvent* last_button_press;
  guint button_press_signal_id;
  gulong button_press_hook_id;

  // Links (`mailto:` URIs) to open, held until Dart takes them with
  // `takeOpenUris`; afterwards they are pushed with `onOpenUris`.
  GPtrArray* pending_uris;
  gboolean dart_takes_uris;

  // Pending debounced window state notification.
  guint state_update_source_id;

  // Last window state sent to Dart, to suppress duplicate notifications.
  gboolean state_sent;
  gboolean state_visible;
  gboolean state_focused;
  gboolean state_maximized;
  gboolean state_fullscreen;
  gboolean state_tiled;

  GCancellable* cancellable;
};

G_DEFINE_TYPE(PlumeMainWindow, plume_main_window, G_TYPE_OBJECT)

// Sends an AppLifecycleState to the framework. The engine's own window state
// monitor only reports changes it sees from GDK, so explicit messages are used
// where GDK gives no event (a window that was never mapped) or to enable
// frames just before mapping.
static void send_lifecycle_state(PlumeMainWindow* self, const gchar* state) {
  FlEngine* engine = fl_view_get_engine(self->view);
  g_autoptr(FlStringCodec) codec = fl_string_codec_new();
  g_autoptr(FlValue) value = fl_value_new_string(state);
  g_autoptr(GError) error = nullptr;
  g_autoptr(GBytes) message =
      fl_message_codec_encode_message(FL_MESSAGE_CODEC(codec), value, &error);
  if (message == nullptr) {
    g_warning("Failed to encode lifecycle state: %s", error->message);
    return;
  }
  fl_binary_messenger_send_on_channel(fl_engine_get_binary_messenger(engine),
                                      kLifecycleChannel, message, nullptr,
                                      nullptr, nullptr);
}

// Invokes a method on the Dart side of the window channel (fire and forget).
static void invoke_dart(PlumeMainWindow* self,
                        const gchar* method,
                        FlValue* args) {
  if (self->channel == nullptr) {
    return;
  }
  fl_method_channel_invoke_method(self->channel, method, args, nullptr,
                                  nullptr, nullptr);
}

// Moves the pending links into a new list value for Dart.
static FlValue* take_pending_uris(PlumeMainWindow* self) {
  FlValue* list = fl_value_new_list();
  for (guint i = 0; i < self->pending_uris->len; i++) {
    fl_value_append_take(list, fl_value_new_string(static_cast<const gchar*>(
                                   g_ptr_array_index(self->pending_uris, i))));
  }
  g_ptr_array_set_size(self->pending_uris, 0);
  return list;
}

// Hands an activation token to GDK so the next focus request may steal focus.
// On Wayland this is an xdg-activation token; on X11 a startup notification id
// (whose `_TIME<n>` suffix also provides the user timestamp).
static void apply_activation_token(PlumeMainWindow* self) {
  g_autofree gchar* token = g_steal_pointer(&self->pending_token);
  if (token == nullptr || token[0] == '\0') {
    return;
  }
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(self->window));
#ifdef GDK_WINDOWING_WAYLAND
  if (GDK_IS_WAYLAND_DISPLAY(display)) {
    gdk_wayland_display_set_startup_notification_id(display, token);
    return;
  }
#endif
#ifdef GDK_WINDOWING_X11
  if (GDK_IS_X11_DISPLAY(display)) {
    gtk_window_set_startup_id(self->window, token);
  }
#endif
}

// Maps, raises and focuses the window now.
static void present_now(PlumeMainWindow* self) {
  self->present_pending = FALSE;
  self->start_hidden = FALSE;

  gboolean was_visible = gtk_widget_get_visible(GTK_WIDGET(self->window));
  if (!was_visible) {
    // Re-enable frames before mapping so a correctly sized frame is produced
    // promptly (GTK only waits briefly for one when drawing).
    send_lifecycle_state(self, kLifecycleInactive);
  }

  apply_activation_token(self);
  if (was_visible) {
    gtk_window_present(self->window);
  } else {
    // Presenting a hidden window only maps it; present again once mapped so
    // GDK also issues a focus (xdg-activation) request with the token.
    gtk_widget_show(GTK_WIDGET(self->window));
    gtk_window_present(self->window);
  }
}

// Hides the window. Rendering stops while hidden; the Dart isolate, timers and
// sockets keep running.
static void hide_window(PlumeMainWindow* self) {
  self->present_pending = FALSE;
  if (!self->have_first_frame) {
    // Do not show the window when the first frame arrives.
    self->start_hidden = TRUE;
  }
  gtk_widget_hide(GTK_WIDGET(self->window));
  send_lifecycle_state(self, kLifecycleHidden);
}

// Reports maximized/fullscreen/focused/visible/tiled to Dart when they change.
static void update_window_state(PlumeMainWindow* self) {
  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(self->window));
  GdkWindowState state = gdk_window != nullptr
                             ? gdk_window_get_state(gdk_window)
                             : GDK_WINDOW_STATE_WITHDRAWN;

  gboolean visible = gtk_widget_get_visible(GTK_WIDGET(self->window)) &&
                     (state & GDK_WINDOW_STATE_ICONIFIED) == 0;
  gboolean focused = visible && (state & GDK_WINDOW_STATE_FOCUSED) != 0;
  gboolean maximized = (state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
  gboolean fullscreen = (state & GDK_WINDOW_STATE_FULLSCREEN) != 0;
  gboolean tiled =
      (state & (GDK_WINDOW_STATE_TILED | GDK_WINDOW_STATE_TOP_TILED |
                GDK_WINDOW_STATE_BOTTOM_TILED | GDK_WINDOW_STATE_LEFT_TILED |
                GDK_WINDOW_STATE_RIGHT_TILED)) != 0;

  if (self->state_sent && visible == self->state_visible &&
      focused == self->state_focused && maximized == self->state_maximized &&
      fullscreen == self->state_fullscreen && tiled == self->state_tiled) {
    return;
  }
  self->state_sent = TRUE;
  self->state_visible = visible;
  self->state_focused = focused;
  self->state_maximized = maximized;
  self->state_fullscreen = fullscreen;
  self->state_tiled = tiled;

  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "maximized", fl_value_new_bool(maximized));
  fl_value_set_string_take(args, "fullscreen", fl_value_new_bool(fullscreen));
  fl_value_set_string_take(args, "focused", fl_value_new_bool(focused));
  fl_value_set_string_take(args, "visible", fl_value_new_bool(visible));
  fl_value_set_string_take(args, "tiled", fl_value_new_bool(tiled));
  invoke_dart(self, "onWindowStateChanged", args);
}

static gboolean state_update_cb(gpointer user_data) {
  PlumeMainWindow* self = PLUME_MAIN_WINDOW(user_data);
  self->state_update_source_id = 0;
  update_window_state(self);
  return G_SOURCE_REMOVE;
}

static void schedule_state_update(PlumeMainWindow* self) {
  if (self->state_update_source_id == 0) {
    self->state_update_source_id =
        g_timeout_add(kStateDebounceMs, state_update_cb, self);
  }
}

// Called when the first Flutter frame is received.
static void first_frame_cb(PlumeMainWindow* self) {
  self->have_first_frame = TRUE;
  if (self->start_hidden && !self->present_pending) {
    // Background launch: keep the window unmapped until Dart asks for it.
    return;
  }
  present_now(self);
}

// Implements GtkWidget::delete-event (the window close button). Connected
// before the view is realized so it runs before FlView's own handler, which
// asks Dart whether the application may exit.
static gboolean delete_event_cb(PlumeMainWindow* self) {
  if (!self->prevent_close) {
    return FALSE;
  }
  hide_window(self);
  invoke_dart(self, "onCloseRequested", nullptr);
  return TRUE;
}

static gboolean window_state_event_cb(PlumeMainWindow* self) {
  schedule_state_update(self);
  return FALSE;
}

// Emission hook for GtkWidget::button-press-event. FlView consumes button
// events, so a hook is the only way to observe them without patching the
// embedder.
static gboolean button_press_hook(GSignalInvocationHint* hint,
                                  guint n_param_values,
                                  const GValue* param_values,
                                  gpointer user_data) {
  PlumeMainWindow* self = PLUME_MAIN_WINDOW(user_data);
  if (n_param_values < 2) {
    return TRUE;
  }
  GObject* instance = G_OBJECT(g_value_get_object(&param_values[0]));
  if (!GTK_IS_WIDGET(instance) ||
      gtk_widget_get_toplevel(GTK_WIDGET(instance)) !=
          GTK_WIDGET(self->window)) {
    return TRUE;
  }
  GdkEvent* event = static_cast<GdkEvent*>(g_value_get_boxed(&param_values[1]));
  if (event != nullptr && event->type == GDK_BUTTON_PRESS) {
    g_clear_pointer(&self->last_button_press, gdk_event_free);
    self->last_button_press = gdk_event_copy(event);
  }
  // Keep the hook installed.
  return TRUE;
}

// Gets the button, root position and timestamp for an interactive move or
// resize, preferring the most recent button press in this window.
static void get_drag_origin(PlumeMainWindow* self,
                            gint* button,
                            gint* root_x,
                            gint* root_y,
                            guint32* timestamp) {
  if (self->last_button_press != nullptr) {
    GdkEventButton* press = &self->last_button_press->button;
    *button = static_cast<gint>(press->button);
    *root_x = static_cast<gint>(press->x_root);
    *root_y = static_cast<gint>(press->y_root);
    *timestamp = press->time;
    return;
  }

  *button = GDK_BUTTON_PRIMARY;
  *timestamp = GDK_CURRENT_TIME;
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(self->window));
  GdkDevice* pointer =
      gdk_seat_get_pointer(gdk_display_get_default_seat(display));
  gdk_device_get_position(pointer, nullptr, root_x, root_y);
}

static gboolean parse_edge(const gchar* name, GdkWindowEdge* edge) {
  static const struct {
    const gchar* name;
    GdkWindowEdge edge;
  } kEdges[] = {
      {"top", GDK_WINDOW_EDGE_NORTH},
      {"bottom", GDK_WINDOW_EDGE_SOUTH},
      {"left", GDK_WINDOW_EDGE_WEST},
      {"right", GDK_WINDOW_EDGE_EAST},
      {"topLeft", GDK_WINDOW_EDGE_NORTH_WEST},
      {"topRight", GDK_WINDOW_EDGE_NORTH_EAST},
      {"bottomLeft", GDK_WINDOW_EDGE_SOUTH_WEST},
      {"bottomRight", GDK_WINDOW_EDGE_SOUTH_EAST},
  };
  if (name == nullptr) {
    return FALSE;
  }
  for (const auto& entry : kEdges) {
    if (strcmp(name, entry.name) == 0) {
      *edge = entry.edge;
      return TRUE;
    }
  }
  return FALSE;
}

// Reads an argument that Dart may send either bare or as `{key: value}`.
static FlValue* get_argument(FlValue* args, const gchar* key) {
  if (args == nullptr) {
    return nullptr;
  }
  if (fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
    return fl_value_lookup_string(args, key);
  }
  return args;
}

static const gchar* get_string_argument(FlValue* args, const gchar* key) {
  FlValue* value = get_argument(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_STRING) {
    return nullptr;
  }
  return fl_value_get_string(value);
}

static gboolean get_bool_argument(FlValue* args,
                                  const gchar* key,
                                  gboolean* result) {
  FlValue* value = get_argument(args, key);
  if (value == nullptr || fl_value_get_type(value) != FL_VALUE_TYPE_BOOL) {
    return FALSE;
  }
  *result = fl_value_get_bool(value);
  return TRUE;
}

// Quits the application from an idle callback, after the `quit` call has been
// answered. Mirrors the embedder's own quit path.
static gboolean quit_idle_cb(gpointer user_data) {
  GApplication* application = g_application_get_default();
  if (application == nullptr) {
    exit(0);
  }
  // GtkApplication windows hold a reference back to the application; break
  // them so it can clean up (https://gitlab.gnome.org/GNOME/gtk/-/issues/6190).
  if (GTK_IS_APPLICATION(application)) {
    g_autoptr(GList) windows = g_list_copy(
        gtk_application_get_windows(GTK_APPLICATION(application)));
    for (GList* link = windows; link != nullptr; link = link->next) {
      gtk_window_set_application(GTK_WINDOW(link->data), nullptr);
    }
  }
  g_application_quit(application);
  return G_SOURCE_REMOVE;
}

static FlMethodResponse* success(FlValue* result = nullptr) {
  return FL_METHOD_RESPONSE(fl_method_success_response_new(result));
}

static FlMethodResponse* bad_arguments(const gchar* message) {
  return FL_METHOD_RESPONSE(
      fl_method_error_response_new("bad-arguments", message, nullptr));
}

// Handles calls from Dart on the `plume/window` channel.
static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  PlumeMainWindow* self = PLUME_MAIN_WINDOW(user_data);
  const gchar* method = fl_method_call_get_name(method_call);
  FlValue* args = fl_method_call_get_args(method_call);
  GtkWindow* window = self->window;

  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(method, "show") == 0) {
    plume_main_window_present(self,
                              get_string_argument(args, "activationToken"));
    response = success();
  } else if (strcmp(method, "hide") == 0) {
    hide_window(self);
    response = success();
  } else if (strcmp(method, "isVisible") == 0) {
    g_autoptr(FlValue) result =
        fl_value_new_bool(gtk_widget_get_visible(GTK_WIDGET(window)));
    response = success(result);
  } else if (strcmp(method, "minimize") == 0) {
    gtk_window_iconify(window);
    response = success();
  } else if (strcmp(method, "toggleMaximize") == 0) {
    if (gtk_window_is_maximized(window)) {
      gtk_window_unmaximize(window);
    } else {
      gtk_window_maximize(window);
    }
    response = success();
  } else if (strcmp(method, "isMaximized") == 0) {
    g_autoptr(FlValue) result =
        fl_value_new_bool(gtk_window_is_maximized(window));
    response = success(result);
  } else if (strcmp(method, "startMove") == 0) {
    gint button, root_x, root_y;
    guint32 timestamp;
    get_drag_origin(self, &button, &root_x, &root_y, &timestamp);
    gtk_window_begin_move_drag(window, button, root_x, root_y, timestamp);
    response = success();
  } else if (strcmp(method, "startResize") == 0) {
    GdkWindowEdge edge;
    if (!parse_edge(get_string_argument(args, "edge"), &edge)) {
      response = bad_arguments("Expected edge: top, bottom, left, right, "
                               "topLeft, topRight, bottomLeft or bottomRight");
    } else {
      gint button, root_x, root_y;
      guint32 timestamp;
      get_drag_origin(self, &button, &root_x, &root_y, &timestamp);
      gtk_window_begin_resize_drag(window, edge, button, root_x, root_y,
                                   timestamp);
      response = success();
    }
  } else if (strcmp(method, "setPreventClose") == 0) {
    gboolean prevent_close;
    if (!get_bool_argument(args, "preventClose", &prevent_close)) {
      response = bad_arguments("Expected a bool");
    } else {
      self->prevent_close = prevent_close;
      response = success();
    }
  } else if (strcmp(method, "setTitle") == 0) {
    const gchar* title = get_string_argument(args, "title");
    if (title == nullptr) {
      response = bad_arguments("Expected a string");
    } else {
      gtk_window_set_title(window, title);
      response = success();
    }
  } else if (strcmp(method, "takeOpenUris") == 0) {
    // Dart is ready for links: return those received so far (e.g. the one
    // Plume was launched with) and push later ones as they arrive.
    self->dart_takes_uris = TRUE;
    g_autoptr(FlValue) result = take_pending_uris(self);
    response = success(result);
  } else if (strcmp(method, "quit") == 0) {
    g_idle_add(quit_idle_cb, nullptr);
    response = success();
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond to %s: %s", method, error->message);
  }
}

static void set_background(PlumeMainWindow* self, gboolean dark) {
  GdkRGBA color;
  gdk_rgba_parse(&color, dark ? kDarkBackground : kLightBackground);
  fl_view_set_background_color(self->view, &color);
}

// Picks the pre-first-frame background from the portal's colour-scheme
// preference (1 = dark, 2 = light) once the asynchronous reply arrives.
static void color_scheme_cb(GObject* source,
                            GAsyncResult* result,
                            gpointer user_data) {
  g_autoptr(GError) error = nullptr;
  g_autoptr(GVariant) reply = g_dbus_connection_call_finish(
      G_DBUS_CONNECTION(source), result, &error);
  if (reply == nullptr) {
    // No portal or no setting: keep the GTK-based guess.
    return;
  }
  // Settings.Read returns the value wrapped in one or two variants.
  g_autoptr(GVariant) value = nullptr;
  g_variant_get(reply, "(v)", &value);
  while (value != nullptr && g_variant_is_of_type(value, G_VARIANT_TYPE_VARIANT)) {
    GVariant* inner = g_variant_get_variant(value);
    g_variant_unref(value);
    value = inner;
  }
  if (value == nullptr || !g_variant_is_of_type(value, G_VARIANT_TYPE_UINT32)) {
    return;
  }
  guint32 scheme = g_variant_get_uint32(value);
  if (scheme == 1 || scheme == 2) {
    set_background(PLUME_MAIN_WINDOW(user_data), scheme == 1);
  }
}

static void setup_background(PlumeMainWindow* self, GApplication* application) {
  // Initial guess from GTK settings; refined by the portal below.
  gboolean prefer_dark = FALSE;
  g_autofree gchar* theme_name = nullptr;
  g_object_get(gtk_settings_get_default(), "gtk-application-prefer-dark-theme",
               &prefer_dark, "gtk-theme-name", &theme_name, nullptr);
  gboolean dark = prefer_dark || (theme_name != nullptr &&
                                  g_str_has_suffix(theme_name, "-dark"));
  set_background(self, dark);

  GDBusConnection* connection = g_application_get_dbus_connection(application);
  if (connection == nullptr) {
    return;
  }
  g_dbus_connection_call(
      connection, "org.freedesktop.portal.Desktop",
      "/org/freedesktop/portal/desktop", "org.freedesktop.portal.Settings",
      "Read",
      g_variant_new("(ss)", "org.freedesktop.appearance", "color-scheme"),
      G_VARIANT_TYPE("(v)"), G_DBUS_CALL_FLAGS_NONE, 500, self->cancellable,
      color_scheme_cb, self);
}

static void plume_main_window_dispose(GObject* object) {
  PlumeMainWindow* self = PLUME_MAIN_WINDOW(object);

  g_cancellable_cancel(self->cancellable);
  if (self->state_update_source_id != 0) {
    g_source_remove(self->state_update_source_id);
    self->state_update_source_id = 0;
  }
  if (self->button_press_hook_id != 0) {
    g_signal_remove_emission_hook(self->button_press_signal_id,
                                  self->button_press_hook_id);
    self->button_press_hook_id = 0;
  }
  if (self->window != nullptr) {
    g_signal_handlers_disconnect_by_data(self->window, self);
  }
  if (self->view != nullptr) {
    g_signal_handlers_disconnect_by_data(self->view, self);
  }
  if (self->channel != nullptr) {
    fl_method_channel_set_method_call_handler(self->channel, nullptr, nullptr,
                                              nullptr);
  }
  g_clear_object(&self->channel);
  g_clear_pointer(&self->last_button_press, gdk_event_free);
  g_clear_pointer(&self->pending_token, g_free);
  g_clear_pointer(&self->pending_uris, g_ptr_array_unref);
  g_clear_object(&self->cancellable);
  self->view = nullptr;
  g_clear_object(&self->window);

  G_OBJECT_CLASS(plume_main_window_parent_class)->dispose(object);
}

static void plume_main_window_class_init(PlumeMainWindowClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = plume_main_window_dispose;
}

static void plume_main_window_init(PlumeMainWindow* self) {
  self->cancellable = g_cancellable_new();
  self->pending_uris = g_ptr_array_new_with_free_func(g_free);
}

PlumeMainWindow* plume_main_window_new(GtkApplication* application,
                                       FlDartProject* project,
                                       gboolean start_hidden,
                                       const gchar* startup_token) {
  PlumeMainWindow* self = PLUME_MAIN_WINDOW(
      g_object_new(plume_main_window_get_type(), nullptr));
  self->start_hidden = start_hidden;
  self->pending_token = g_strdup(startup_token);

  GtkWindow* window = GTK_WINDOW(gtk_application_window_new(application));
  self->window = GTK_WINDOW(g_object_ref(window));
  gtk_window_set_title(window, kWindowTitle);
  // Wayland resolves the installed desktop icon by name. Also set the bundled
  // artwork explicitly for X11, including uninstalled development builds.
  gtk_window_set_icon_name(window, "org.atinus.plume");
  g_autofree gchar* icon_path = g_build_filename(
      fl_dart_project_get_assets_path(project), "assets", "branding", "plume.png",
      nullptr);
  gtk_window_set_icon_from_file(window, icon_path, nullptr);
  gtk_window_set_default_size(window, kDefaultWidth, kDefaultHeight);

  // Hide the native title bar so Flutter can draw its own title area. An
  // empty custom titlebar makes GTK use client-side decorations, which keeps
  // the shadow and resize edges on compositors that expect CSD (GNOME) and
  // overrides server-side title bars (KDE, X11 window managers). The widget
  // is never shown, so it takes no space and no header bar is drawn; tiling
  // compositors (Hyprland, sway) report tiled states and GTK drops the shadow.
  GtkWidget* titlebar = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
  gtk_widget_set_size_request(titlebar, -1, 0);
  gtk_window_set_titlebar(window, titlebar);

  // Must be connected before the view is realized (see delete_event_cb).
  g_signal_connect_swapped(window, "delete-event", G_CALLBACK(delete_event_cb),
                           self);
  g_signal_connect_swapped(window, "window-state-event",
                           G_CALLBACK(window_state_event_cb), self);
  g_signal_connect_swapped(window, "show", G_CALLBACK(schedule_state_update),
                           self);
  g_signal_connect_swapped(window, "hide", G_CALLBACK(schedule_state_update),
                           self);

  self->view = fl_view_new(project);
  setup_background(self, G_APPLICATION(application));
  gtk_widget_set_size_request(GTK_WIDGET(self->view), kMinimumWidth,
                              kMinimumHeight);
  gtk_widget_show(GTK_WIDGET(self->view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(self->view));

  // The window channel is ready before Dart starts running.
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(self->view)),
      kWindowChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb,
                                            self, nullptr);

  // Track button presses for startMove/startResize.
  self->button_press_signal_id =
      g_signal_lookup("button-press-event", GTK_TYPE_WIDGET);
  self->button_press_hook_id = g_signal_add_emission_hook(
      self->button_press_signal_id, 0, button_press_hook, self, nullptr);

  // Show the window when Flutter renders (unless starting in the background).
  // Realizing the view starts the engine and the Dart isolate without
  // mapping the window.
  g_signal_connect_swapped(self->view, "first-frame",
                           G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(self->view));

  if (start_hidden) {
    // GDK reports no state change for a window that was never mapped, so tell
    // the framework it is hidden: it then schedules no frames until shown.
    send_lifecycle_state(self, kLifecycleHidden);
  }

  fl_register_plugins(FL_PLUGIN_REGISTRY(self->view));

  gtk_widget_grab_focus(GTK_WIDGET(self->view));

  return self;
}

void plume_main_window_present(PlumeMainWindow* self,
                               const gchar* activation_token) {
  g_return_if_fail(PLUME_IS_MAIN_WINDOW(self));

  if (activation_token != nullptr && activation_token[0] != '\0') {
    g_free(self->pending_token);
    self->pending_token = g_strdup(activation_token);
  }

  if (!self->have_first_frame) {
    // Show as soon as the first frame is ready. Frames may be disabled after a
    // background launch, so enable them.
    self->present_pending = TRUE;
    send_lifecycle_state(self, kLifecycleInactive);
    return;
  }
  present_now(self);
}

void plume_main_window_notify_activated(PlumeMainWindow* self,
                                        const gchar* activation_token) {
  g_return_if_fail(PLUME_IS_MAIN_WINDOW(self));

  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "activationToken",
                           activation_token != nullptr
                               ? fl_value_new_string(activation_token)
                               : fl_value_new_null());
  invoke_dart(self, "onActivated", args);
}

void plume_main_window_open_uris(PlumeMainWindow* self, gchar** uris) {
  g_return_if_fail(PLUME_IS_MAIN_WINDOW(self));

  for (gchar** uri = uris; uri != nullptr && *uri != nullptr; uri++) {
    g_ptr_array_add(self->pending_uris, g_strdup(*uri));
  }
  if (self->dart_takes_uris && self->pending_uris->len > 0) {
    g_autoptr(FlValue) args = take_pending_uris(self);
    invoke_dart(self, "onOpenUris", args);
  }
}

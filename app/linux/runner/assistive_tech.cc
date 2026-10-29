#include "assistive_tech.h"

#include <cstring>

namespace {

constexpr char kChannel[] = "plume/accessibility";
constexpr char kMethod[] = "assistiveTech";

// Set to 1 to keep semantics on, or 0 to keep them off, whatever AT-SPI says.
constexpr char kForceEnv[] = "GNOME_ACCESSIBILITY";

}  // namespace

struct _PlumeAssistiveTech {
  GObject parent_instance;

  FlMethodChannel* channel;

  // AT-SPI's org.a11y.Status, once the lookup has finished (NULL if there is
  // no session bus).
  GDBusProxy* status;

  // TRUE once the lookup has finished.
  gboolean known;

  GCancellable* cancellable;
};

G_DEFINE_TYPE(PlumeAssistiveTech, plume_assistive_tech, G_TYPE_OBJECT)

// Whether an assistive technology may be reading the app. With no
// accessibility bus nothing can read the semantics, so it's FALSE then.
static gboolean is_enabled(PlumeAssistiveTech* self) {
  const gchar* forced = g_getenv(kForceEnv);
  if (forced != nullptr) {
    return g_strcmp0(forced, "0") != 0;
  }
  if (self->status == nullptr) {
    return FALSE;
  }
  // Newer AT-SPI only has IsEnabled.
  static const gchar* const kFlags[] = {"IsEnabled", "ScreenReaderEnabled"};
  for (const gchar* name : kFlags) {
    g_autoptr(GVariant) value =
        g_dbus_proxy_get_cached_property(self->status, name);
    if (value != nullptr &&
        g_variant_is_of_type(value, G_VARIANT_TYPE_BOOLEAN) &&
        g_variant_get_boolean(value)) {
      return TRUE;
    }
  }
  return FALSE;
}

static void send_enabled(PlumeAssistiveTech* self) {
  g_autoptr(FlValue) value = fl_value_new_bool(is_enabled(self));
  fl_method_channel_invoke_method(self->channel, kMethod, value, nullptr,
                                  nullptr, nullptr);
}

static void status_ready_cb(GObject* source,
                            GAsyncResult* result,
                            gpointer user_data) {
  g_autoptr(GError) error = nullptr;
  GDBusProxy* proxy = g_dbus_proxy_new_for_bus_finish(result, &error);
  // Cancelled on dispose; user_data is gone then.
  if (g_error_matches(error, G_IO_ERROR, G_IO_ERROR_CANCELLED)) {
    return;
  }
  PlumeAssistiveTech* self = PLUME_ASSISTIVE_TECH(user_data);
  self->status = proxy;
  self->known = TRUE;
  if (proxy != nullptr) {
    // The flags change when a screen reader starts or stops, and the
    // accessibility bus may only appear after Plume does.
    g_signal_connect_swapped(proxy, "g-properties-changed",
                             G_CALLBACK(send_enabled), self);
    g_signal_connect_swapped(proxy, "notify::g-name-owner",
                             G_CALLBACK(send_enabled), self);
  }
  send_enabled(self);
}

// Handles calls from Dart: whether a screen reader may be listening. Null
// until the D-Bus lookup has finished; the answer is sent then, and again
// whenever it changes.
static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* method_call,
                           gpointer user_data) {
  PlumeAssistiveTech* self = PLUME_ASSISTIVE_TECH(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;
  if (strcmp(fl_method_call_get_name(method_call), kMethod) == 0) {
    g_autoptr(FlValue) value = self->known || g_getenv(kForceEnv) != nullptr
                                   ? fl_value_new_bool(is_enabled(self))
                                   : fl_value_new_null();
    response = FL_METHOD_RESPONSE(fl_method_success_response_new(value));
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond to %s: %s",
              fl_method_call_get_name(method_call), error->message);
  }
}

static void plume_assistive_tech_dispose(GObject* object) {
  PlumeAssistiveTech* self = PLUME_ASSISTIVE_TECH(object);

  g_cancellable_cancel(self->cancellable);
  g_clear_object(&self->cancellable);
  if (self->status != nullptr) {
    g_signal_handlers_disconnect_by_data(self->status, self);
    g_clear_object(&self->status);
  }
  if (self->channel != nullptr) {
    fl_method_channel_set_method_call_handler(self->channel, nullptr, nullptr,
                                              nullptr);
  }
  g_clear_object(&self->channel);

  G_OBJECT_CLASS(plume_assistive_tech_parent_class)->dispose(object);
}

static void plume_assistive_tech_class_init(PlumeAssistiveTechClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = plume_assistive_tech_dispose;
}

static void plume_assistive_tech_init(PlumeAssistiveTech* self) {
  self->cancellable = g_cancellable_new();
}

PlumeAssistiveTech* plume_assistive_tech_new(FlBinaryMessenger* messenger) {
  PlumeAssistiveTech* self = PLUME_ASSISTIVE_TECH(
      g_object_new(plume_assistive_tech_get_type(), nullptr));

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel =
      fl_method_channel_new(messenger, kChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb,
                                            self, nullptr);

  // Never starts the accessibility bus just to ask; GTK does that when an
  // assistive technology needs it.
  g_dbus_proxy_new_for_bus(G_BUS_TYPE_SESSION,
                           G_DBUS_PROXY_FLAGS_DO_NOT_AUTO_START, nullptr,
                           "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Status",
                           self->cancellable, status_ready_cb, self);
  return self;
}

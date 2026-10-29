#include "mail_renderer.h"

#include <gtk/gtk.h>
#include <webkit2/webkit2.h>

#include <cmath>
#include <cstring>

namespace {

constexpr char kChannel[] = "plume/mail_renderer";

// Custom scheme for the documents themselves (each render gets its own path
// under kOrigin) and for the fonts they use. Sharing the origin lets
// @font-face load the bundled font without CORS.
constexpr char kScheme[] = "plume";
constexpr char kOrigin[] = "plume://mail/";
constexpr char kFontPath[] = "/fonts/plume-sans.ttf";
constexpr char kFontAsset[] = "packages/plume_design/fonts/GoogleSansFlex.ttf";

// Web views rendering concurrently. They share one web process; the second
// one keeps a message with slow remote images from holding up the rest.
constexpr guint kMaxSlots = 2;

// Remote images may keep a document loading; after this long, render what
// has arrived.
constexpr guint kSoftTimeoutMs = 4000;
// Fail a render whose document has not even been parsed after this long.
constexpr guint kHardTimeoutMs = 15000;
// Re-check interval while waiting for a slow document to commit.
constexpr guint kRetryMs = 250;

// Snapshot rows per tile, so each tile fits in a GPU texture.
constexpr gint kTileRows = 2048;
// Cairo image surfaces are limited to 32767 pixels per side.
constexpr gint kMaxSide = 32000;
constexpr gint64 kDefaultMaxPixels = 24ll * 1024 * 1024;
// Shrinking wide layouts to fit stops here; past it they are clipped.
constexpr gdouble kMinFit = 0.3;

// The script result marking a document that is not the requested one yet
// (an earlier load is still reporting events).
constexpr char kStale[] = "__plume_stale__";

constexpr char kMeasureScript[] =
    "[document.documentElement.scrollWidth, innerWidth,"
    " document.documentElement.scrollHeight]";

}  // namespace

typedef enum {
  STATE_IDLE,
  STATE_RESIZING,
  STATE_LOADING,
  STATE_PREPARING,
  STATE_FITTING,
  STATE_COLLECTING,
  STATE_MEASURING,
  STATE_SNAPSHOT,
} SlotState;

typedef struct {
  gint64 id;
  // Unique per job; async callbacks compare it to ignore results that
  // arrive after their job ended.
  guint64 serial;
  FlMethodCall* call;
  gchar* uri;
  gchar* html;
  gchar* prepare;
  gchar* collect;
  gchar* options;
  gdouble width;  // CSS px
  gdouble scale;  // device px per CSS px
  GdkRGBA background;
  gint64 max_pixels;

  gboolean timed_out;
  gint64 started_at;

  // Results so far.
  gchar* prepared;
  gchar* collected;
  gint widget_width;  // GTK units
  gdouble zoom;
  gdouble viewport_width;  // CSS px
  gdouble content_height;  // CSS px
} Job;

typedef struct _Slot Slot;
typedef void (*SlotContinuation)(Slot* slot);

struct _Slot {
  PlumeMailRenderer* renderer;
  GtkWidget* window;  // GtkOffscreenWindow, owns the view
  WebKitWebView* view;
  SlotState state;
  Job* job;
  // The only URI the view may navigate to.
  gchar* allowed_uri;
  guint timeout_id;
  guint hard_timeout_id;
  // Pending wait for the view to take a new size.
  gulong size_allocate_id;
  guint resize_timeout_id;
  SlotContinuation after_resize;
};

struct _PlumeMailRenderer {
  GObject parent_instance;

  FlMethodChannel* channel;
  WebKitWebContext* context;
  gchar* font_file;
  GBytes* font;
  Slot* slots[kMaxSlots];
  GQueue* queue;
  guint64 next_serial;
};

G_DEFINE_TYPE(PlumeMailRenderer, plume_mail_renderer, G_TYPE_OBJECT)

static void pump(PlumeMailRenderer* self);
static void start_load(Slot* slot);
static void run_prepare(Slot* slot);

static void job_free(Job* job) {
  g_clear_object(&job->call);
  g_free(job->uri);
  g_free(job->html);
  g_free(job->prepare);
  g_free(job->collect);
  g_free(job->options);
  g_free(job->prepared);
  g_free(job->collected);
  g_free(job);
}

// An async operation started for the job a slot is running.
typedef struct {
  Slot* slot;
  guint64 serial;
} Op;

static gpointer op_new(Slot* slot) {
  Op* op = g_new(Op, 1);
  op->slot = slot;
  op->serial = slot->job->serial;
  return op;
}

// Frees [data] and returns its slot, or null if the slot has moved on to
// another job (or none) since the operation started.
static Slot* op_finish(gpointer data) {
  Op* op = static_cast<Op*>(data);
  Slot* slot = op->slot;
  guint64 serial = op->serial;
  g_free(op);
  return slot->job != nullptr && slot->job->serial == serial ? slot : nullptr;
}

static void respond(FlMethodCall* call, FlMethodResponse* response) {
  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(call, response, &error)) {
    g_warning("Failed to respond to mail render: %s", error->message);
  }
}

static void respond_error(FlMethodCall* call,
                          const gchar* code,
                          const gchar* message) {
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_error_response_new(code, message, nullptr));
  respond(call, response);
}

static void clear_sources(Slot* slot) {
  if (slot->timeout_id != 0) {
    g_source_remove(slot->timeout_id);
    slot->timeout_id = 0;
  }
  if (slot->hard_timeout_id != 0) {
    g_source_remove(slot->hard_timeout_id);
    slot->hard_timeout_id = 0;
  }
  if (slot->size_allocate_id != 0) {
    g_signal_handler_disconnect(slot->view, slot->size_allocate_id);
    slot->size_allocate_id = 0;
  }
  if (slot->resize_timeout_id != 0) {
    g_source_remove(slot->resize_timeout_id);
    slot->resize_timeout_id = 0;
  }
  slot->after_resize = nullptr;
}

// Ends the slot's job with an error and moves on to the next one.
static void fail(Slot* slot, const gchar* code, const gchar* message) {
  Job* job = slot->job;
  clear_sources(slot);
  slot->job = nullptr;
  slot->state = STATE_IDLE;
  if (job != nullptr) {
    respond_error(job->call, code, message);
    job_free(job);
  }
  pump(slot->renderer);
}

// Serves the bundled font to documents.
static void scheme_request_cb(WebKitURISchemeRequest* request,
                              gpointer user_data) {
  PlumeMailRenderer* self = PLUME_MAIL_RENDERER(user_data);
  const gchar* path = webkit_uri_scheme_request_get_path(request);
  if (g_strcmp0(path, kFontPath) == 0 && self->font == nullptr) {
    gchar* contents = nullptr;
    gsize length = 0;
    if (g_file_get_contents(self->font_file, &contents, &length, nullptr)) {
      self->font = g_bytes_new_take(contents, length);
    }
  }
  if (g_strcmp0(path, kFontPath) != 0 || self->font == nullptr) {
    g_autoptr(GError) error =
        g_error_new_literal(G_IO_ERROR, G_IO_ERROR_NOT_FOUND, "Not found");
    webkit_uri_scheme_request_finish_error(request, error);
    return;
  }
  g_autoptr(GInputStream) stream =
      g_memory_input_stream_new_from_bytes(self->font);
  webkit_uri_scheme_request_finish(request, stream,
                                   g_bytes_get_size(self->font), "font/ttf");
}

// Mail may not navigate: only the document being rendered is loaded.
static gboolean decide_policy_cb(WebKitWebView* view,
                                 WebKitPolicyDecision* decision,
                                 WebKitPolicyDecisionType type,
                                 gpointer user_data) {
  Slot* slot = static_cast<Slot*>(user_data);
  if (type == WEBKIT_POLICY_DECISION_TYPE_NAVIGATION_ACTION) {
    WebKitNavigationAction* action =
        webkit_navigation_policy_decision_get_navigation_action(
            WEBKIT_NAVIGATION_POLICY_DECISION(decision));
    const gchar* uri =
        webkit_uri_request_get_uri(webkit_navigation_action_get_request(action));
    if (slot->allowed_uri != nullptr && g_strcmp0(uri, slot->allowed_uri) == 0) {
      webkit_policy_decision_use(decision);
    } else {
      webkit_policy_decision_ignore(decision);
    }
    return TRUE;
  }
  if (type == WEBKIT_POLICY_DECISION_TYPE_NEW_WINDOW_ACTION) {
    webkit_policy_decision_ignore(decision);
    return TRUE;
  }
  return FALSE;
}

static gboolean deny_permission_cb(WebKitWebView* view,
                                   WebKitPermissionRequest* request,
                                   gpointer user_data) {
  webkit_permission_request_deny(request);
  return TRUE;
}

static void load_changed_cb(WebKitWebView* view,
                            WebKitLoadEvent event,
                            gpointer user_data) {
  Slot* slot = static_cast<Slot*>(user_data);
  if (event != WEBKIT_LOAD_FINISHED || slot->state != STATE_LOADING ||
      slot->job == nullptr) {
    return;
  }
  // Earlier loads may still report here; run_prepare checks that the
  // document is the requested one before using it.
  run_prepare(slot);
}

static void web_process_terminated_cb(WebKitWebView* view,
                                      WebKitWebProcessTerminationReason reason,
                                      gpointer user_data) {
  Slot* slot = static_cast<Slot*>(user_data);
  g_warning("Mail web process terminated (%d)", reason);
  if (slot->job != nullptr) {
    fail(slot, "failed", "The web process stopped");
  }
}

static gboolean soft_timeout_cb(gpointer user_data) {
  Slot* slot = static_cast<Slot*>(user_data);
  slot->timeout_id = 0;
  if (slot->state == STATE_LOADING && slot->job != nullptr) {
    run_prepare(slot);
  }
  return G_SOURCE_REMOVE;
}

static gboolean hard_timeout_cb(gpointer user_data) {
  Slot* slot = static_cast<Slot*>(user_data);
  slot->hard_timeout_id = 0;
  if (slot->job == nullptr) {
    return G_SOURCE_REMOVE;
  }
  if (slot->state == STATE_LOADING) {
    webkit_web_view_stop_loading(slot->view);
    fail(slot, "failed", "Timed out");
  } else {
    // A check of the document is in flight; fail if it finds none.
    slot->job->timed_out = TRUE;
  }
  return G_SOURCE_REMOVE;
}

static Slot* slot_new(PlumeMailRenderer* self, WebKitWebView* related) {
  Slot* slot = g_new0(Slot, 1);
  slot->renderer = self;

  // Related views share the first view's web process.
  slot->view = WEBKIT_WEB_VIEW(
      related != nullptr
          ? g_object_new(WEBKIT_TYPE_WEB_VIEW, "related-view", related, nullptr)
          : g_object_new(WEBKIT_TYPE_WEB_VIEW, "web-context", self->context,
                         nullptr));

  WebKitSettings* settings = webkit_web_view_get_settings(slot->view);
  g_object_set(
      settings, "enable-javascript-markup", FALSE,
      "javascript-can-open-windows-automatically", FALSE,
      "javascript-can-access-clipboard", FALSE, "allow-modal-dialogs", FALSE,
      "enable-html5-local-storage", FALSE, "enable-page-cache", FALSE,
      "enable-webgl", FALSE, "enable-webaudio", FALSE, "enable-media", FALSE,
      "enable-media-stream", FALSE, "enable-mediasource", FALSE,
      "enable-encrypted-media", FALSE, "enable-developer-extras", FALSE, "enable-smooth-scrolling", FALSE,
      "enable-resizable-text-areas", FALSE, "enable-tabs-to-links", FALSE,
      "allow-file-access-from-file-urls", FALSE,
      "allow-universal-access-from-file-urls", FALSE,
      "media-playback-requires-user-gesture", TRUE,
      // Software rendering is what snapshots need, and it keeps the GPU free
      // for Flutter.
      "hardware-acceleration-policy", WEBKIT_HARDWARE_ACCELERATION_POLICY_NEVER,
      nullptr);

  g_signal_connect(slot->view, "decide-policy", G_CALLBACK(decide_policy_cb),
                   slot);
  g_signal_connect(slot->view, "permission-request",
                   G_CALLBACK(deny_permission_cb), slot);
  g_signal_connect(slot->view, "load-changed", G_CALLBACK(load_changed_cb),
                   slot);
  g_signal_connect(slot->view, "web-process-terminated",
                   G_CALLBACK(web_process_terminated_cb), slot);

  slot->window = gtk_offscreen_window_new();
  gtk_widget_set_size_request(GTK_WIDGET(slot->view), 600, 1);
  gtk_container_add(GTK_CONTAINER(slot->window), GTK_WIDGET(slot->view));
  gtk_widget_show_all(slot->window);
  return slot;
}

static void slot_free(Slot* slot) {
  clear_sources(slot);
  g_signal_handlers_disconnect_by_data(slot->view, slot);
  gtk_widget_destroy(slot->window);
  g_free(slot->allowed_uri);
  if (slot->job != nullptr) {
    job_free(slot->job);
  }
  g_free(slot);
}

static void resize_done(Slot* slot) {
  SlotContinuation next = slot->after_resize;
  if (slot->size_allocate_id != 0) {
    g_signal_handler_disconnect(slot->view, slot->size_allocate_id);
    slot->size_allocate_id = 0;
  }
  if (slot->resize_timeout_id != 0) {
    g_source_remove(slot->resize_timeout_id);
    slot->resize_timeout_id = 0;
  }
  slot->after_resize = nullptr;
  if (next != nullptr && slot->job != nullptr) {
    next(slot);
  }
}

static void size_allocate_cb(GtkWidget* widget,
                             GdkRectangle* allocation,
                             gpointer user_data) {
  resize_done(static_cast<Slot*>(user_data));
}

static gboolean resize_timeout_cb(gpointer user_data) {
  Slot* slot = static_cast<Slot*>(user_data);
  slot->resize_timeout_id = 0;
  resize_done(slot);
  return G_SOURCE_REMOVE;
}

// Sizes the view to [width] GTK units wide (and 1 tall, so documents
// measure at their content height) with [zoom], then continues with [next]
// once the view has the new size.
static void configure(Slot* slot,
                      gint width,
                      gdouble zoom,
                      SlotContinuation next) {
  webkit_web_view_set_zoom_level(slot->view, zoom);
  if (gtk_widget_get_allocated_width(GTK_WIDGET(slot->view)) == width) {
    next(slot);
    return;
  }
  slot->state = STATE_RESIZING;
  slot->after_resize = next;
  slot->size_allocate_id = g_signal_connect_after(
      slot->view, "size-allocate", G_CALLBACK(size_allocate_cb), slot);
  slot->resize_timeout_id = g_timeout_add(500, resize_timeout_cb, slot);
  gtk_widget_set_size_request(GTK_WIDGET(slot->view), width, 1);
  gtk_window_resize(GTK_WINDOW(slot->window), width, 1);
}

static void start_load(Slot* slot) {
  Job* job = slot->job;
  slot->state = STATE_LOADING;
  g_free(slot->allowed_uri);
  slot->allowed_uri = g_strdup(job->uri);
  webkit_web_view_set_background_color(slot->view, &job->background);
  webkit_web_view_load_html(slot->view, job->html, job->uri);
  // The HTML is no longer needed; drop the copy early.
  g_clear_pointer(&job->html, g_free);
  slot->timeout_id = g_timeout_add(kSoftTimeoutMs, soft_timeout_cb, slot);
  slot->hard_timeout_id = g_timeout_add(kHardTimeoutMs, hard_timeout_cb, slot);
}

static GVariant* script_arguments(Job* job) {
  GVariantBuilder builder;
  g_variant_builder_init(&builder, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&builder, "{sv}", "options",
                        g_variant_new_string(job->options));
  g_variant_builder_add(&builder, "{sv}", "documentUri",
                        g_variant_new_string(job->uri));
  return g_variant_builder_end(&builder);
}

// Returns the string a script resolved to, or null (setting [error]).
static gchar* script_result(GObject* source,
                            GAsyncResult* result,
                            GError** error) {
  g_autoptr(JSCValue) value =
      webkit_web_view_call_async_javascript_function_finish(
          WEBKIT_WEB_VIEW(source), result, error);
  if (value == nullptr) {
    return nullptr;
  }
  if (!jsc_value_is_string(value)) {
    g_set_error_literal(error, G_IO_ERROR, G_IO_ERROR_INVALID_DATA,
                        "Script returned no string");
    return nullptr;
  }
  return jsc_value_to_string(value);
}

static void snapshot_cb(GObject* source, GAsyncResult* result, gpointer data);
static void measure_cb(GObject* source, GAsyncResult* result, gpointer data);

static void take_snapshot(Slot* slot) {
  slot->state = STATE_SNAPSHOT;
  webkit_web_view_get_snapshot(slot->view, WEBKIT_SNAPSHOT_REGION_FULL_DOCUMENT,
                               WEBKIT_SNAPSHOT_OPTIONS_NONE, nullptr,
                               snapshot_cb, op_new(slot));
}

static void run_measure(Slot* slot) {
  slot->state = slot->job->collected == nullptr ? STATE_FITTING
                                                : STATE_MEASURING;
  webkit_web_view_evaluate_javascript(slot->view, kMeasureScript, -1, nullptr,
                                      nullptr, nullptr, measure_cb,
                                      op_new(slot));
}

static void collect_cb(GObject* source, GAsyncResult* result, gpointer data) {
  Slot* slot = op_finish(data);
  g_autoptr(GError) error = nullptr;
  gchar* collected = script_result(source, result, &error);
  if (slot == nullptr) {
    g_free(collected);
    return;
  }
  if (collected == nullptr) {
    fail(slot, "failed", error->message);
    return;
  }
  slot->job->collected = collected;
  run_measure(slot);
}

static void run_collect(Slot* slot) {
  Job* job = slot->job;
  slot->state = STATE_COLLECTING;
  webkit_web_view_call_async_javascript_function(
      slot->view, job->collect, -1, script_arguments(job), nullptr, nullptr,
      nullptr, collect_cb, op_new(slot));
}

// Shrinks wide layouts to fit (before collecting), then checks the pixel
// budget (after collecting) and snapshots.
static void measure_cb(GObject* source, GAsyncResult* result, gpointer data) {
  Slot* slot = op_finish(data);
  g_autoptr(GError) error = nullptr;
  g_autoptr(JSCValue) value = webkit_web_view_evaluate_javascript_finish(
      WEBKIT_WEB_VIEW(source), result, &error);
  if (slot == nullptr) {
    return;
  }
  if (value == nullptr || !jsc_value_is_array(value)) {
    fail(slot, "failed", error != nullptr ? error->message : "Bad measurement");
    return;
  }
  g_autoptr(JSCValue) v0 = jsc_value_object_get_property_at_index(value, 0);
  g_autoptr(JSCValue) v1 = jsc_value_object_get_property_at_index(value, 1);
  g_autoptr(JSCValue) v2 = jsc_value_object_get_property_at_index(value, 2);
  gdouble scroll_width = jsc_value_to_double(v0);
  gdouble viewport_width = jsc_value_to_double(v1);
  gdouble scroll_height = jsc_value_to_double(v2);
  Job* job = slot->job;

  if (slot->state == STATE_FITTING) {
    if (scroll_width > viewport_width + 1 && viewport_width > 0) {
      // A fixed-width layout wider than the pane: zoom out so it fits, as
      // mail apps on small screens do, instead of clipping it.
      gdouble fit = MAX(viewport_width / scroll_width, kMinFit);
      job->zoom *= fit;
      webkit_web_view_set_zoom_level(slot->view, job->zoom);
    }
    run_collect(slot);
    return;
  }

  job->viewport_width = viewport_width;
  job->content_height = MAX(scroll_height, 1.0);

  // Keep the snapshot within the pixel budget and cairo's limits by
  // rendering fewer device pixels per CSS pixel; the layout is unchanged.
  gint gtk_scale = gtk_widget_get_scale_factor(GTK_WIDGET(slot->view));
  gdouble device_scale = job->zoom * gtk_scale;
  gdouble pixel_width = job->widget_width * gtk_scale;
  gdouble pixel_height = ceil(job->content_height * device_scale);
  gdouble k = 1.0;
  if (pixel_width * pixel_height > job->max_pixels) {
    k = sqrt(job->max_pixels / (pixel_width * pixel_height));
  }
  k = MIN(k, kMaxSide / pixel_height);
  k = MIN(k, kMaxSide / pixel_width);
  if (k < 0.99) {
    gint width = MAX(1, (gint)floor(job->widget_width * k));
    job->zoom *= (gdouble)width / job->widget_width;
    job->widget_width = width;
    configure(slot, width, job->zoom, take_snapshot);
    return;
  }
  take_snapshot(slot);
}

static void prepare_cb(GObject* source, GAsyncResult* result, gpointer data) {
  Slot* slot = op_finish(data);
  g_autoptr(GError) error = nullptr;
  gchar* prepared = script_result(source, result, &error);
  if (slot == nullptr) {
    g_free(prepared);
    return;
  }
  if (prepared != nullptr && strcmp(prepared, kStale) == 0) {
    g_free(prepared);
    if (slot->job->timed_out) {
      fail(slot, "failed", "Timed out");
      return;
    }
    // The requested document has not been committed yet. Wait for its load
    // to finish, or retry shortly if that already happened.
    slot->state = STATE_LOADING;
    if (slot->timeout_id == 0) {
      slot->timeout_id = g_timeout_add(kRetryMs, soft_timeout_cb, slot);
    }
    return;
  }
  if (prepared == nullptr) {
    fail(slot, "failed", error->message);
    return;
  }
  // The document is ready; slow remote resources no longer matter.
  if (slot->hard_timeout_id != 0) {
    g_source_remove(slot->hard_timeout_id);
    slot->hard_timeout_id = 0;
  }
  slot->job->prepared = prepared;
  run_measure(slot);
}

static void run_prepare(Slot* slot) {
  Job* job = slot->job;
  if (slot->timeout_id != 0) {
    g_source_remove(slot->timeout_id);
    slot->timeout_id = 0;
  }
  slot->state = STATE_PREPARING;
  // Guard against running in an earlier document that is still loading or
  // reporting events.
  g_autofree gchar* body = g_strconcat(
      "if (location.href !== documentUri) return '", kStale, "';\n",
      job->prepare, nullptr);
  webkit_web_view_call_async_javascript_function(
      slot->view, body, -1, script_arguments(job), nullptr, nullptr, nullptr,
      prepare_cb, op_new(slot));
}

// Splits [surface] into tiles of RGBA rows (premultiplied).
static FlValue* tiles_from_surface(cairo_surface_t* surface,
                                   gint* out_width,
                                   gint* out_height) {
  g_autoptr(FlValue) tiles = fl_value_new_list();
  cairo_surface_t* image = cairo_surface_reference(surface);
  if (cairo_surface_get_type(surface) != CAIRO_SURFACE_TYPE_IMAGE) {
    double x1, y1, x2, y2;
    cairo_t* probe = cairo_create(surface);
    cairo_clip_extents(probe, &x1, &y1, &x2, &y2);
    cairo_destroy(probe);
    cairo_surface_destroy(image);
    image = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, (int)(x2 - x1),
                                       (int)(y2 - y1));
    cairo_t* cr = cairo_create(image);
    cairo_set_source_surface(cr, surface, -x1, -y1);
    cairo_paint(cr);
    cairo_destroy(cr);
  }
  cairo_surface_flush(image);
  gint width = cairo_image_surface_get_width(image);
  gint height = cairo_image_surface_get_height(image);
  gint stride = cairo_image_surface_get_stride(image);
  gboolean opaque_format =
      cairo_image_surface_get_format(image) == CAIRO_FORMAT_RGB24;
  // Cairo stores native-endian 32-bit ARGB, i.e. BGRA bytes on the
  // little-endian machines Plume runs on.
  G_STATIC_ASSERT(G_BYTE_ORDER == G_LITTLE_ENDIAN);
  const guint8* data = cairo_image_surface_get_data(image);
  gsize row_bytes = (gsize)width * 4;
  for (gint top = 0; data != nullptr && top < height; top += kTileRows) {
    gint rows = MIN(kTileRows, height - top);
    g_autofree guint8* tile = static_cast<guint8*>(g_malloc(row_bytes * rows));
    for (gint y = 0; y < rows; y++) {
      const guint8* in = data + (gsize)stride * (top + y);
      guint8* out = tile + row_bytes * y;
      for (gint x = 0; x < width; x++, in += 4, out += 4) {
        out[0] = in[2];
        out[1] = in[1];
        out[2] = in[0];
        out[3] = opaque_format ? 0xff : in[3];
      }
    }
    fl_value_append_take(tiles, fl_value_new_uint8_list(tile, row_bytes * rows));
  }
  cairo_surface_destroy(image);
  *out_width = width;
  *out_height = height;
  return fl_value_ref(tiles);
}

static void snapshot_cb(GObject* source, GAsyncResult* result, gpointer data) {
  Slot* slot = op_finish(data);
  g_autoptr(GError) error = nullptr;
  cairo_surface_t* surface = webkit_web_view_get_snapshot_finish(
      WEBKIT_WEB_VIEW(source), result, &error);
  if (slot == nullptr) {
    if (surface != nullptr) {
      cairo_surface_destroy(surface);
    }
    return;
  }
  if (surface == nullptr) {
    fail(slot, "failed", error->message);
    return;
  }

  Job* job = slot->job;
  gint width = 0, height = 0;
  g_autoptr(FlValue) tiles = tiles_from_surface(surface, &width, &height);
  cairo_surface_destroy(surface);

  g_autoptr(FlValue) map = fl_value_new_map();
  fl_value_set_string_take(map, "width", fl_value_new_int(width));
  fl_value_set_string_take(map, "height", fl_value_new_int(height));
  fl_value_set_string_take(map, "tileRows", fl_value_new_int(kTileRows));
  fl_value_set_string(map, "tiles", tiles);
  fl_value_set_string_take(map, "viewportWidth",
                           fl_value_new_float(job->viewport_width));
  fl_value_set_string_take(map, "contentHeight",
                           fl_value_new_float(job->content_height));
  fl_value_set_string_take(map, "prepared", fl_value_new_string(job->prepared));
  fl_value_set_string_take(map, "collected",
                           fl_value_new_string(job->collected));
  fl_value_set_string_take(
      map, "elapsedMs",
      fl_value_new_int((g_get_monotonic_time() - job->started_at) / 1000));

  clear_sources(slot);
  slot->job = nullptr;
  slot->state = STATE_IDLE;
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(map));
  respond(job->call, response);
  job_free(job);
  pump(slot->renderer);
}

static Slot* idle_slot(PlumeMailRenderer* self) {
  for (guint i = 0; i < kMaxSlots; i++) {
    if (self->slots[i] == nullptr) {
      self->slots[i] =
          slot_new(self, i == 0 ? nullptr : self->slots[0]->view);
      return self->slots[i];
    }
    if (self->slots[i]->state == STATE_IDLE) {
      return self->slots[i];
    }
  }
  return nullptr;
}

// Starts queued jobs on idle slots.
static void pump(PlumeMailRenderer* self) {
  while (!g_queue_is_empty(self->queue)) {
    Slot* slot = idle_slot(self);
    if (slot == nullptr) {
      return;
    }
    Job* job = static_cast<Job*>(g_queue_pop_head(self->queue));
    job->serial = ++self->next_serial;
    slot->job = job;
    job->started_at = g_get_monotonic_time();
    gint gtk_scale = gtk_widget_get_scale_factor(GTK_WIDGET(slot->view));
    job->widget_width =
        MAX(1, (gint)round(job->width * job->scale / gtk_scale));
    job->zoom = job->scale / gtk_scale;
    configure(slot, job->widget_width, job->zoom, start_load);
  }
}

static const gchar* string_arg(FlValue* args, const gchar* key) {
  FlValue* value = fl_value_lookup_string(args, key);
  return value != nullptr && fl_value_get_type(value) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(value)
             : nullptr;
}

static gboolean number_arg(FlValue* args, const gchar* key, gdouble* out) {
  FlValue* value = fl_value_lookup_string(args, key);
  if (value == nullptr) {
    return FALSE;
  }
  switch (fl_value_get_type(value)) {
    case FL_VALUE_TYPE_FLOAT:
      *out = fl_value_get_float(value);
      return TRUE;
    case FL_VALUE_TYPE_INT:
      *out = (gdouble)fl_value_get_int(value);
      return TRUE;
    default:
      return FALSE;
  }
}

static void handle_render(PlumeMailRenderer* self, FlMethodCall* call) {
  FlValue* args = fl_method_call_get_args(call);
  gdouble id, width, scale, background, max_pixels;
  const gchar* html = nullptr;
  const gchar* prepare = nullptr;
  const gchar* collect = nullptr;
  if (fl_value_get_type(args) != FL_VALUE_TYPE_MAP ||
      !number_arg(args, "id", &id) || !number_arg(args, "width", &width) ||
      !number_arg(args, "scale", &scale) ||
      !number_arg(args, "background", &background) ||
      (html = string_arg(args, "html")) == nullptr ||
      (prepare = string_arg(args, "prepare")) == nullptr ||
      (collect = string_arg(args, "collect")) == nullptr || width < 1 ||
      scale <= 0) {
    respond_error(call, "bad-arguments",
                  "Expected id, width, scale, background, html, prepare and "
                  "collect");
    return;
  }
  if (!number_arg(args, "maxPixels", &max_pixels) || max_pixels < 1) {
    max_pixels = (gdouble)kDefaultMaxPixels;
  }
  const gchar* options = string_arg(args, "options");

  Job* job = g_new0(Job, 1);
  job->id = (gint64)id;
  job->call = FL_METHOD_CALL(g_object_ref(call));
  job->uri = g_strdup_printf("%s%" G_GINT64_FORMAT "/", kOrigin, job->id);
  job->html = g_strdup(html);
  job->prepare = g_strdup(prepare);
  job->collect = g_strdup(collect);
  job->options = g_strdup(options != nullptr ? options : "{}");
  job->width = width;
  job->scale = MIN(scale, 4.0);
  job->max_pixels = (gint64)max_pixels;
  guint32 argb = (guint32)(gint64)background;
  job->background.alpha = 1.0;
  job->background.red = ((argb >> 16) & 0xff) / 255.0;
  job->background.green = ((argb >> 8) & 0xff) / 255.0;
  job->background.blue = (argb & 0xff) / 255.0;
  g_queue_push_tail(self->queue, job);
  pump(self);
}

static void handle_cancel(PlumeMailRenderer* self, FlMethodCall* call) {
  gdouble id;
  if (!number_arg(fl_method_call_get_args(call), "id", &id)) {
    respond_error(call, "bad-arguments", "Expected id");
    return;
  }
  for (GList* l = self->queue->head; l != nullptr; l = l->next) {
    Job* job = static_cast<Job*>(l->data);
    if (job->id == (gint64)id) {
      g_queue_delete_link(self->queue, l);
      respond_error(job->call, "cancelled", "Cancelled");
      job_free(job);
      break;
    }
  }
  for (guint i = 0; i < kMaxSlots; i++) {
    Slot* slot = self->slots[i];
    if (slot == nullptr || slot->job == nullptr ||
        slot->job->id != (gint64)id) {
      continue;
    }
    // Results still in flight are dropped when they arrive.
    if (slot->state == STATE_LOADING) {
      webkit_web_view_stop_loading(slot->view);
    }
    fail(slot, "cancelled", "Cancelled");
  }
  g_autoptr(FlMethodResponse) response =
      FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
  respond(call, response);
}

static void method_call_cb(FlMethodChannel* channel,
                           FlMethodCall* call,
                           gpointer user_data) {
  PlumeMailRenderer* self = PLUME_MAIL_RENDERER(user_data);
  const gchar* method = fl_method_call_get_name(call);
  if (strcmp(method, "render") == 0) {
    handle_render(self, call);
  } else if (strcmp(method, "cancel") == 0) {
    handle_cancel(self, call);
  } else if (strcmp(method, "warmUp") == 0) {
    // Start the web process ahead of the first message.
    Slot* slot = idle_slot(self);
    if (slot != nullptr) {
      g_free(slot->allowed_uri);
      slot->allowed_uri = g_strdup_printf("%swarm-up/", kOrigin);
      webkit_web_view_load_html(slot->view, "", slot->allowed_uri);
    }
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    respond(call, response);
  } else {
    g_autoptr(FlMethodResponse) response =
        FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
    respond(call, response);
  }
}

static void plume_mail_renderer_dispose(GObject* object) {
  PlumeMailRenderer* self = PLUME_MAIL_RENDERER(object);
  if (self->channel != nullptr) {
    fl_method_channel_set_method_call_handler(self->channel, nullptr, nullptr,
                                              nullptr);
  }
  g_clear_object(&self->channel);
  // Related views go first; the first view owns the web process.
  for (gint i = kMaxSlots - 1; i >= 0; i--) {
    g_clear_pointer(&self->slots[i], slot_free);
  }
  if (self->queue != nullptr) {
    g_queue_free_full(self->queue, [](gpointer job) {
      job_free(static_cast<Job*>(job));
    });
    self->queue = nullptr;
  }
  g_clear_object(&self->context);
  g_clear_pointer(&self->font, g_bytes_unref);
  g_clear_pointer(&self->font_file, g_free);
  G_OBJECT_CLASS(plume_mail_renderer_parent_class)->dispose(object);
}

static void plume_mail_renderer_class_init(PlumeMailRendererClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = plume_mail_renderer_dispose;
}

static void plume_mail_renderer_init(PlumeMailRenderer* self) {
  self->queue = g_queue_new();
}

PlumeMailRenderer* plume_mail_renderer_new(FlBinaryMessenger* messenger,
                                           const gchar* assets_path) {
  PlumeMailRenderer* self = PLUME_MAIL_RENDERER(
      g_object_new(plume_mail_renderer_get_type(), nullptr));
  self->font_file = g_build_filename(assets_path, kFontAsset, nullptr);

  // Nothing a message does is kept: no cookies, caches or storage on disk.
  self->context = webkit_web_context_new_ephemeral();
  webkit_web_context_set_cache_model(self->context,
                                     WEBKIT_CACHE_MODEL_DOCUMENT_BROWSER);
  webkit_web_context_register_uri_scheme(self->context, kScheme,
                                         scheme_request_cb, self, nullptr);

  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->channel =
      fl_method_channel_new(messenger, kChannel, FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(self->channel, method_call_cb, self,
                                            nullptr);
  return self;
}

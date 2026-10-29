#ifndef RUNNER_MAIL_RENDERER_H_
#define RUNNER_MAIL_RENDERER_H_

#include <flutter_linux/flutter_linux.h>

G_DECLARE_FINAL_TYPE(PlumeMailRenderer,
                     plume_mail_renderer,
                     PLUME,
                     MAIL_RENDERER,
                     GObject)

/**
 * plume_mail_renderer_new:
 * @messenger: the engine's binary messenger.
 * @assets_path: the Flutter assets directory (fonts are served from it).
 *
 * Renders HTML mail with WebKitGTK in offscreen web views and returns the
 * pixels to Dart over the `plume/mail_renderer` method channel. Mail is
 * laid out by a real browser engine, so `<style>` sheets, media queries and
 * table layouts render as in other mail clients, while Flutter keeps
 * control of scrolling, clipping and animation.
 *
 * Mail runs with JavaScript markup disabled, in an ephemeral session, and
 * may not navigate. Remote content is governed by the Content Security
 * Policy Dart puts in each document.
 *
 * Returns: a new #PlumeMailRenderer.
 */
PlumeMailRenderer* plume_mail_renderer_new(FlBinaryMessenger* messenger,
                                           const gchar* assets_path);

#endif  // RUNNER_MAIL_RENDERER_H_

#ifndef RUNNER_MAIN_WINDOW_H_
#define RUNNER_MAIN_WINDOW_H_

#include <flutter_linux/flutter_linux.h>
#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(PlumeMainWindow,
                     plume_main_window,
                     PLUME,
                     MAIN_WINDOW,
                     GObject)

/**
 * plume_main_window_new:
 * @application: the application that owns the window.
 * @project: the Dart project to run.
 * @start_hidden: %TRUE to start the Flutter engine without ever showing the
 *   window (the `--background` launch mode). The Dart isolate still runs.
 * @startup_token: (nullable): the XDG activation token / startup id this
 *   process was launched with, used when the window is first presented.
 *
 * Creates the main window, starts the Flutter engine and exposes the
 * `plume/window` method channel to Dart.
 *
 * Returns: a new #PlumeMainWindow.
 */
PlumeMainWindow* plume_main_window_new(GtkApplication* application,
                                       FlDartProject* project,
                                       gboolean start_hidden,
                                       const gchar* startup_token);

/**
 * plume_main_window_present:
 * @self: a #PlumeMainWindow.
 * @activation_token: (nullable): an xdg-activation token (Wayland) or startup
 *   notification id (X11) that allows the window to take focus.
 *
 * Shows, raises and focuses the window. If Flutter has not produced its first
 * frame yet, the window is shown as soon as it has.
 */
void plume_main_window_present(PlumeMainWindow* self,
                               const gchar* activation_token);

/**
 * plume_main_window_notify_activated:
 * @self: a #PlumeMainWindow.
 * @activation_token: (nullable): the token the activating launch carried.
 *
 * Sends `onActivated` to Dart, e.g. when a second instance was launched.
 */
void plume_main_window_notify_activated(PlumeMainWindow* self,
                                        const gchar* activation_token);

#endif  // RUNNER_MAIN_WINDOW_H_

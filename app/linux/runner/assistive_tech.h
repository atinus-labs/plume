#ifndef RUNNER_ASSISTIVE_TECH_H_
#define RUNNER_ASSISTIVE_TECH_H_

#include <flutter_linux/flutter_linux.h>

G_DECLARE_FINAL_TYPE(PlumeAssistiveTech,
                     plume_assistive_tech,
                     PLUME,
                     ASSISTIVE_TECH,
                     GObject)

/**
 * plume_assistive_tech_new:
 * @messenger: the engine's binary messenger.
 *
 * Tells Dart, over the `plume/accessibility` method channel, whether a
 * screen reader or another assistive technology may be reading Plume, so
 * that Dart only builds Flutter's semantics tree while one is.
 *
 * Elsewhere Flutter builds that tree only while such a tool is on, but the
 * Linux embedder turns it on unconditionally, and keeping it current costs
 * several milliseconds of every animated frame.
 *
 * Follows AT-SPI's org.a11y.Status, which is what Qt, Chromium and Firefox
 * check, and honours GNOME_ACCESSIBILITY=1 (or 0) as they do.
 *
 * Returns: a new #PlumeAssistiveTech.
 */
PlumeAssistiveTech* plume_assistive_tech_new(FlBinaryMessenger* messenger);

#endif  // RUNNER_ASSISTIVE_TECH_H_

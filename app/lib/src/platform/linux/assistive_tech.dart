import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Whether a screen reader or another assistive technology may be reading
/// Plume, and so needs Flutter's semantics tree.
///
/// Elsewhere Flutter only builds that tree while such a tool is on, but the
/// Linux embedder asks for it unconditionally, and keeping it current costs
/// several milliseconds of every animated frame. So on Linux the runner
/// watches AT-SPI (linux/runner/assistive_tech.cc, over
/// `plume/accessibility`) and Plume leaves semantics out while nothing is
/// listening. `GNOME_ACCESSIBILITY=1` keeps them on.
///
/// True wherever that isn't known, so accessibility never goes missing.
class AssistiveTech extends ValueNotifier<bool> {
  AssistiveTech._() : super(true);

  static final instance = AssistiveTech._();

  static const _channel = MethodChannel('plume/accessibility');

  static bool get supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

  bool _watching = false;

  /// Starts following the runner's reports.
  Future<void> watch() async {
    if (!supported || _watching) return;
    _watching = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'assistiveTech' && call.arguments is bool) value = call.arguments as bool;
    });
    try {
      // Null while the runner is still asking D-Bus; it reports back then.
      final listening = await _channel.invokeMethod<bool>('assistiveTech');
      if (listening != null) value = listening;
    } on Exception {
      // Older runner: semantics stay on.
    }
  }
}

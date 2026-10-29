import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:plume_design/plume_design.dart';

/// On-screen controls that keyboard shortcuts stand for.
enum ShortcutTarget { compose, archive, delete, spam, unread, newer, older }

/// The last shortcut used, numbered so repeats count.
final shortcutEchoProvider = NotifierProvider<ShortcutEchoNotifier, (ShortcutTarget, int)?>(ShortcutEchoNotifier.new);

class ShortcutEchoNotifier extends Notifier<(ShortcutTarget, int)?> {
  var _count = 0;

  @override
  (ShortcutTarget, int)? build() => null;

  void echo(ShortcutTarget target) => state = (target, ++_count);
}

/// Presses [child] when the shortcut for [target] is used, so the keyboard
/// gets the same answer as a click.
class ShortcutEcho extends ConsumerWidget {
  const ShortcutEcho({super.key, required this.target, required this.child, this.shape = const CircleBorder()});

  final ShortcutTarget target;
  final ShapeBorder shape;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trigger = ref.watch(shortcutEchoProvider.select((e) => e?.$1 == target ? e!.$2 : null));
    return Press(trigger: trigger, shape: shape, child: child);
  }
}

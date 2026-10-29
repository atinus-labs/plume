import 'package:flutter/foundation.dart';

/// What sits at the top of Plume's window.
enum TitleBar {
  /// Plume's own, with window buttons in Plume's style.
  plume('Plume'),

  /// The desktop's own title bar.
  system('System'),

  /// None, for tiling window managers.
  none('None');

  const TitleBar(this.label);

  final String label;
}

/// A button in Plume's title bar.
enum WindowButton { minimize, maximize, close }

/// The window around Plume, where Plume decorates it itself (Linux): which
/// window buttons the desktop asks for and on which side, and whether the
/// window is maximised. Notifies its listeners when either changes.
abstract class WindowFrame extends ChangeNotifier {
  /// The title bar until the user picks one: none on tiling compositors,
  /// where windows go without, and Plume's elsewhere.
  TitleBar get defaultStyle;

  /// Switches to [style]. Call before the first frame to avoid a flash of
  /// the wrong title bar.
  Future<void> apply(TitleBar style);

  bool get maximized;

  /// Window buttons before the app's name, as the desktop lays them out.
  List<WindowButton> get leading;

  /// Window buttons at the far end of the title bar.
  List<WindowButton> get trailing;

  /// Moves the window with the pointer. Call while the button is held.
  Future<void> startMove();

  /// Opens the window manager's window menu, as a right-click on a title bar
  /// does. Call from the press.
  Future<void> showMenu();

  Future<void> minimize();

  Future<void> toggleMaximize();
}

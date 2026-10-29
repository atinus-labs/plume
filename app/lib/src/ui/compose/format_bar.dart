import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'rich_text.dart';

/// One button of the formatting bar.
class _Tool {
  const _Tool(
    this.icon,
    this.label, {
    required this.rank,
    this.shortcut,
    this.selected = false,
    this.onPressed,
    this.choices,
    this.iconColor,
  });

  final IconData icon;
  final String label;

  /// Narrow windows move tools into the overflow menu, lowest rank first.
  final int rank;
  final SingleActivator? shortcut;
  final bool selected;
  final VoidCallback? onPressed;

  /// A menu of choices instead of an action: sizes or colours.
  final Widget Function(BuildContext context)? choices;
  final Color? iconColor;

  String get tooltip => shortcut == null ? label : '$label (${_describe(shortcut!)})';

  static String _describe(SingleActivator s) => [
        if (s.control) 'Ctrl',
        if (s.shift) 'Shift',
        switch (s.trigger) {
          LogicalKeyboardKey.backslash => r'\',
          LogicalKeyboardKey.bracketLeft => '[',
          LogicalKeyboardKey.bracketRight => ']',
          final key => key.keyLabel,
        },
      ].join('+');
}

/// Formatting buttons above the compose actions, like Gmail's formatting
/// bar. Tools that do not fit move into a menu at its end.
class FormatBar extends StatelessWidget {
  const FormatBar({super.key, required this.controller, required this.onFormat, required this.onLink});

  final QuillController controller;

  /// Applies a formatting action and returns focus to the body.
  final void Function(VoidCallback action) onFormat;
  final VoidCallback onLink;

  static const _button = 36.0;
  static const _gap = 9.0;
  static const _padding = 4.0;

  List<List<_Tool>> _groups() {
    _Tool style(IconData icon, String label, Attribute<Object?> attribute, LogicalKeyboardKey key, int rank,
            {bool shift = false}) =>
        _Tool(
          icon,
          label,
          rank: rank,
          shortcut: SingleActivator(key, control: true, shift: shift),
          selected: controller.isActive(attribute),
          onPressed: () => onFormat(() => controller.toggle(attribute)),
        );
    final size = controller.textSize;
    final color = controller.textColor;
    final list = controller.listKind;
    return [
      [
        _Tool(
          Symbols.undo_rounded,
          'Undo',
          rank: 0,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, control: true),
          onPressed: controller.hasUndo ? () => onFormat(controller.undo) : null,
        ),
        _Tool(
          Symbols.redo_rounded,
          'Redo',
          rank: 0,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true),
          onPressed: controller.hasRedo ? () => onFormat(controller.redo) : null,
        ),
      ],
      [
        style(Symbols.format_bold_rounded, 'Bold', Attribute.bold, LogicalKeyboardKey.keyB, 10),
        style(Symbols.format_italic_rounded, 'Italic', Attribute.italic, LogicalKeyboardKey.keyI, 9),
        style(Symbols.format_underlined_rounded, 'Underline', Attribute.underline, LogicalKeyboardKey.keyU, 8),
        style(Symbols.strikethrough_s_rounded, 'Strikethrough', Attribute.strikeThrough, LogicalKeyboardKey.keyX, 3,
            shift: true),
      ],
      [
        _Tool(
          Symbols.format_size_rounded,
          'Size',
          rank: 6,
          selected: size != TextSize.normal,
          choices: (context) => _SizeMenu(selected: size, onSelected: (s) => onFormat(() => controller.setTextSize(s))),
        ),
        _Tool(
          Symbols.format_color_text_rounded,
          'Text colour',
          rank: 6,
          iconColor: color,
          choices: (context) =>
              _ColorMenu(selected: color, onSelected: (c) => onFormat(() => controller.setTextColor(c))),
        ),
      ],
      [
        _Tool(
          Symbols.link_rounded,
          'Insert link',
          rank: 5,
          shortcut: const SingleActivator(LogicalKeyboardKey.keyK, control: true),
          selected: controller.linkRange() != null,
          onPressed: onLink,
        ),
      ],
      [
        _Tool(
          Symbols.format_list_numbered_rounded,
          'Numbered list',
          rank: 7,
          shortcut: const SingleActivator(LogicalKeyboardKey.digit7, control: true, shift: true),
          selected: list == 'ordered',
          onPressed: () => onFormat(() => controller.toggle(Attribute.ol)),
        ),
        _Tool(
          Symbols.format_list_bulleted_rounded,
          'Bulleted list',
          rank: 7,
          shortcut: const SingleActivator(LogicalKeyboardKey.digit8, control: true, shift: true),
          selected: list == 'bullet',
          onPressed: () => onFormat(() => controller.toggle(Attribute.ul)),
        ),
        _Tool(
          Symbols.format_quote_rounded,
          'Quote',
          rank: 4,
          shortcut: const SingleActivator(LogicalKeyboardKey.digit9, control: true, shift: true),
          selected: controller.isActive(Attribute.blockQuote),
          onPressed: () => onFormat(() => controller.toggle(Attribute.blockQuote)),
        ),
      ],
      [
        _Tool(
          Symbols.format_indent_decrease_rounded,
          'Indent less',
          rank: 2,
          shortcut: const SingleActivator(LogicalKeyboardKey.bracketLeft, control: true),
          onPressed: controller.indentLevel > 0 ? () => onFormat(() => controller.indentSelection(false)) : null,
        ),
        _Tool(
          Symbols.format_indent_increase_rounded,
          'Indent more',
          rank: 2,
          shortcut: const SingleActivator(LogicalKeyboardKey.bracketRight, control: true),
          onPressed: controller.indentLevel < 5 ? () => onFormat(() => controller.indentSelection(true)) : null,
        ),
      ],
      [
        _Tool(
          Symbols.format_clear_rounded,
          'Remove formatting',
          rank: 1,
          shortcut: const SingleActivator(LogicalKeyboardKey.backslash, control: true),
          onPressed: () => onFormat(controller.clearFormatting),
        ),
      ],
    ];
  }

  /// The tools that fit in [width], in order and grouped, and the rest.
  static (List<List<_Tool>>, List<List<_Tool>>) _fit(List<List<_Tool>> groups, double width) {
    var hidden = -1;
    List<List<_Tool>> shown() => [
          for (final g in groups)
            if (g.where((t) => t.rank > hidden).toList() case final s when s.isNotEmpty) s,
        ];
    double widthOf(List<List<_Tool>> s) {
      final tools = s.fold(0, (n, g) => n + g.length);
      final overflow = hidden >= 0 ? _gap + _button : 0;
      return 2 * _padding + tools * _button + (s.length - 1) * _gap + overflow;
    }

    final ranks = {for (final g in groups) for (final t in g) t.rank}.toList()..sort();
    var visible = shown();
    for (final rank in ranks) {
      if (widthOf(visible) <= width) break;
      hidden = rank;
      visible = shown();
    }
    final rest = [
      for (final g in groups)
        if (g.where((t) => t.rank <= hidden).toList() case final s when s.isNotEmpty) s,
    ];
    return (visible, rest);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selectedStyle = ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? scheme.secondaryContainer : null,
      ),
      foregroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? scheme.onSurface.withValues(alpha: 0.38)
            : states.contains(WidgetState.selected)
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
      ),
    );

    Widget button(_Tool tool, VoidCallback? onPressed) => IconButton(
          tooltip: tool.tooltip,
          isSelected: tool.selected,
          style: selectedStyle,
          visualDensity: const VisualDensity(horizontal: -3, vertical: -3),
          iconSize: 20,
          onPressed: onPressed,
          icon: Icon(tool.icon, color: tool.iconColor),
        );

    Widget tool(_Tool tool) {
      final choices = tool.choices;
      if (choices == null) return button(tool, tool.onPressed);
      return MenuAnchor(
        menuChildren: [Builder(builder: choices)],
        builder: (context, menu, _) => button(tool, () => menu.isOpen ? menu.close() : menu.open()),
      );
    }

    Widget divider() => SizedBox(
          width: _gap,
          height: 20,
          child: VerticalDivider(width: _gap, color: scheme.outlineVariant.withValues(alpha: 0.6)),
        );

    // Clicking a button must not take the selection away from the body.
    return TextFieldTapRegion(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 2, 12, 0),
        child: LayoutBuilder(
          builder: (context, constraints) => ListenableBuilder(
            listenable: controller,
            builder: (context, _) {
              final (visible, rest) = _fit(_groups(), constraints.maxWidth);
              return Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: scheme.surfaceContainerHigh,
                  shape: const StadiumBorder(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: _padding, vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (i, group) in visible.indexed) ...[
                          if (i > 0) divider(),
                          for (final t in group) tool(t),
                        ],
                        if (rest.isNotEmpty) ...[
                          divider(),
                          _Overflow(groups: rest, button: button),
                        ],
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The tools that did not fit, as a menu.
class _Overflow extends StatelessWidget {
  const _Overflow({required this.groups, required this.button});

  final List<List<_Tool>> groups;
  final Widget Function(_Tool tool, VoidCallback? onPressed) button;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget item(_Tool tool) {
      final icon = Icon(tool.icon, size: 20, color: tool.iconColor);
      if (tool.choices case final choices?) {
        return SubmenuButton(leadingIcon: icon, menuChildren: [Builder(builder: choices)], child: Text(tool.label));
      }
      return MenuItemButton(
        leadingIcon: icon,
        trailingIcon: tool.selected ? Icon(Symbols.check_rounded, size: 18, color: scheme.primary) : null,
        shortcut: tool.shortcut,
        onPressed: tool.onPressed,
        child: Text(tool.label),
      );
    }

    return MenuAnchor(
      menuChildren: [
        for (final (i, group) in groups.indexed) ...[
          if (i > 0) const Divider(height: 8),
          for (final t in group) item(t),
        ],
      ],
      builder: (context, menu, _) => button(
        const _Tool(Symbols.more_horiz_rounded, 'More formatting', rank: 0),
        () => menu.isOpen ? menu.close() : menu.open(),
      ),
    );
  }
}

/// Text sizes, each shown at its size.
class _SizeMenu extends StatelessWidget {
  const _SizeMenu({required this.selected, required this.onSelected});

  final TextSize selected;
  final ValueChanged<TextSize> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final size in TextSize.values)
          MenuItemButton(
            leadingIcon: SizedBox(
              width: 20,
              child: size == selected ? Icon(Symbols.check_rounded, size: 18, color: theme.colorScheme.primary) : null,
            ),
            onPressed: () => onSelected(size),
            child: Text(size.label, style: base.copyWith(fontSize: base.fontSize! * size.scale)),
          ),
      ],
    );
  }
}

/// A grid of text colours and the default.
class _ColorMenu extends StatelessWidget {
  const _ColorMenu({required this.selected, required this.onSelected});

  final Color? selected;
  final ValueChanged<Color?> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget dot(Color? color, {required bool chosen}) => Container(
          width: 24,
          height: 24,
          decoration: ShapeDecoration(
            color: color ?? scheme.onSurface,
            shape: CircleBorder(
              side: chosen ? BorderSide(color: scheme.onSurface, width: 2, strokeAlign: 3) : BorderSide.none,
            ),
          ),
          child: chosen ? Icon(Symbols.check_rounded, size: 16, color: color == null ? scheme.surface : Colors.white) : null,
        );

    // Menu items, so choosing one closes the whole menu.
    Widget swatch(String name, Color color) {
      final chosen = color.toARGB32() == selected?.toARGB32();
      return Tooltip(
        message: name,
        child: MenuItemButton(
          style: const ButtonStyle(
            padding: WidgetStatePropertyAll(EdgeInsets.zero),
            minimumSize: WidgetStatePropertyAll(Size.square(40)),
            maximumSize: WidgetStatePropertyAll(Size.square(40)),
            shape: WidgetStatePropertyAll(CircleBorder()),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => onSelected(color),
          child: Semantics(label: name, selected: chosen, child: Center(child: dot(color, chosen: chosen))),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: SizedBox(
            width: 5 * 40,
            child: Wrap(children: [for (final (name, color) in textColors) swatch(name, color)]),
          ),
        ),
        MenuItemButton(
          leadingIcon: dot(null, chosen: selected == null),
          onPressed: () => onSelected(null),
          child: const Text('Default'),
        ),
      ],
    );
  }
}

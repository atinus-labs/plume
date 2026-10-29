// Quill marks its list markers, key handling and Markdown-style list
// shortcuts experimental.
// ignore_for_file: experimental_member_use

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart';

import 'rich_text.dart';

/// Runs a callback from a keyboard shortcut in the body.
class _Run extends Intent {
  const _Run(this.run);

  final VoidCallback run;
}

/// A shortcut of the editor's that mail has no use for. Nothing handles it,
/// so the key goes on to the app's own shortcuts.
class _Unbound extends Intent {
  const _Unbound();
}

/// The compose body: a rich text editor drawn in the app's body text, with
/// Gmail's formatting shortcuts.
class BodyEditor extends StatelessWidget {
  const BodyEditor({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.onEditLink,
    this.minHeight,
  });

  final QuillController controller;
  final FocusNode focusNode;

  /// Unused while the body scrolls with the rest of the form, but required.
  final ScrollController scrollController;
  final VoidCallback onEditLink;
  final double? minHeight;

  /// Space before a list item's text, and the further step of each nested
  /// level, in ems. HTML lists are written with the same padding.
  static const listIndent = 1.5;

  /// The step of an indented paragraph, in ems: Gmail's 40px.
  static const paragraphIndent = 2.5;

  /// Space between a quote's bar and its text, in ems.
  static const quotePadding = 0.75;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.textTheme.bodyLarge!.copyWith(color: theme.colorScheme.onSurface);
    return QuillEditor(
      controller: controller,
      focusNode: focusNode,
      scrollController: scrollController,
      config: QuillEditorConfig(
        scrollable: false,
        padding: EdgeInsets.zero,
        minHeight: minHeight,
        placeholder: 'Write your message',
        customStyles: _styles(theme.colorScheme, base),
        customLeadingBlockBuilder: (node, config) => _leading(node, config, base.fontSize!),
        textSpanBuilder: (context, node, offset, text, style, recognizer) => TextSpan(
          text: text,
          style: _withAxes(style, node.style.attributes, base),
          recognizer: recognizer,
          mouseCursor: recognizer != null ? SystemMouseCursors.click : null,
        ),
        // "1. " and "- " at the start of a line begin a list.
        spaceShortcutEvents: [formatOrderedNumberToList, formatHyphenToBulletList],
        onKeyPressed: _onKey,
        customShortcuts: _shortcuts(),
        customActions: {
          _Run: CallbackAction<_Run>(onInvoke: (intent) {
            intent.run();
            return null;
          }),
        },
      ),
    );
  }

  /// Tab nests list items and Shift+Tab lifts them, as in Gmail. Elsewhere
  /// the keys move between controls.
  KeyEventResult? _onKey(KeyEvent event, Node? node) {
    if (event.logicalKey != LogicalKeyboardKey.tab || event is KeyUpEvent) return null;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isAltPressed || keyboard.isMetaPressed) return null;
    if (node is Line && node.style.containsKey(Attribute.list.key)) {
      controller.indentSelection(!keyboard.isShiftPressed);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Map<ShortcutActivator, Intent> _shortcuts() {
    _Run toggle(Attribute<Object?> attribute) => _Run(() => controller.toggle(attribute));
    const unbound = _Unbound();
    return {
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): const RedoTextIntent(
        SelectionChangedCause.keyboard,
      ),
      const SingleActivator(LogicalKeyboardKey.keyX, control: true, shift: true): toggle(Attribute.strikeThrough),
      const SingleActivator(LogicalKeyboardKey.keyK, control: true): _Run(onEditLink),
      // Shifted digits may arrive as the digit or as its symbol.
      const SingleActivator(LogicalKeyboardKey.digit7, control: true, shift: true): toggle(Attribute.ol),
      const SingleActivator(LogicalKeyboardKey.ampersand, control: true, shift: true): toggle(Attribute.ol),
      const SingleActivator(LogicalKeyboardKey.digit8, control: true, shift: true): toggle(Attribute.ul),
      const SingleActivator(LogicalKeyboardKey.asterisk, control: true, shift: true): toggle(Attribute.ul),
      const SingleActivator(LogicalKeyboardKey.digit9, control: true, shift: true): toggle(Attribute.blockQuote),
      const SingleActivator(LogicalKeyboardKey.parenthesisLeft, control: true, shift: true): toggle(
        Attribute.blockQuote,
      ),
      const SingleActivator(LogicalKeyboardKey.bracketRight, control: true): _Run(
        () => controller.indentSelection(true),
      ),
      const SingleActivator(LogicalKeyboardKey.bracketLeft, control: true): _Run(
        () => controller.indentSelection(false),
      ),
      const SingleActivator(LogicalKeyboardKey.backslash, control: true): _Run(controller.clearFormatting),
      // Code, headings, checklists, images and search.
      const SingleActivator(LogicalKeyboardKey.backquote, control: true): unbound,
      const SingleActivator(LogicalKeyboardKey.tilde, control: true, shift: true): unbound,
      const SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true): unbound,
      for (final digit in const [
        LogicalKeyboardKey.digit0,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
      ])
        SingleActivator(digit, control: true): unbound,
      const SingleActivator(LogicalKeyboardKey.keyG, control: true): unbound,
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): unbound,
    };
  }

  static DefaultStyles _styles(ColorScheme scheme, TextStyle base) {
    const flat = VerticalSpacing.zero;
    DefaultTextBlockStyle block(TextStyle style, [BoxDecoration? decoration]) =>
        DefaultTextBlockStyle(style, HorizontalSpacing.zero, flat, flat, decoration);
    final size = base.fontSize!;
    return DefaultStyles(
      paragraph: block(base),
      leading: block(base),
      indent: block(base),
      align: block(base),
      placeHolder: block(base.copyWith(color: scheme.onSurfaceVariant)),
      lists: DefaultListBlockStyle(
        base,
        HorizontalSpacing.zero,
        flat,
        flat,
        null,
        null,
        indentWidthBuilder: _indentWidth,
      ),
      quote: block(
        base,
        BoxDecoration(border: Border(left: BorderSide(width: 3, color: scheme.outlineVariant))),
      ),
      color: base.color,
      bold: const TextStyle(fontWeight: FontWeight.w700),
      link: TextStyle(color: scheme.primary, decoration: TextDecoration.underline, decorationColor: scheme.primary),
      sizeSmall: TextStyle(fontSize: size * TextSize.small.scale),
      sizeLarge: TextStyle(fontSize: size * TextSize.large.scale),
      sizeHuge: TextStyle(fontSize: size * TextSize.huge.scale),
    );
  }

  /// The left margin of a list, quote or indented block.
  static HorizontalSpacing _indentWidth(
    Block block,
    BuildContext context,
    int count,
    LeadingBlockNumberPointWidth numberPointWidth,
  ) {
    final em = QuillStyles.getStyles(context, false)?.paragraph?.style.fontSize ?? 16;
    final attrs = block.style.attributes;
    final level = (attrs[Attribute.indent.key]?.value as int?) ?? 0;
    if (attrs.containsKey(Attribute.blockQuote.key)) {
      return HorizontalSpacing(em * (quotePadding + level * paragraphIndent), 0);
    }
    if (attrs.containsKey(Attribute.list.key)) {
      // Room for "10." and up at the first level; deeper levels have their
      // parents' margin too.
      final digits = attrs[Attribute.list.key] == Attribute.ol ? '$count'.length : 1;
      final first = digits < 2 ? listIndent : listIndent + 0.6 * (digits - 1);
      return HorizontalSpacing(em * (first + level * listIndent), 0);
    }
    return HorizontalSpacing(em * level * paragraphIndent, 0);
  }

  /// Bullets that change with depth, as HTML draws nested lists, and
  /// numbers that run 1, a, i. A marker sits on its item's baseline, which
  /// larger text in the item moves down.
  static Widget? _leading(Node node, LeadingConfig config, double baseSize) {
    final style = config.style;
    if (style == null || node is! Line) return null;
    final InlineSpan marker;
    if (config.attribute == Attribute.ol) {
      marker = TextSpan(text: '${config.getIndexNumberByIndent}.');
    } else if (config.attribute == Attribute.ul) {
      final level = (node.style.attributes[Attribute.indent.key]?.value as int?) ?? 0;
      marker = WidgetSpan(
        alignment: PlaceholderAlignment.aboveBaseline,
        baseline: TextBaseline.alphabetic,
        child: _Bullet(style: style, shape: _BulletShape.values[level % 3]),
      );
    } else {
      return null;
    }
    final em = style.fontSize ?? baseSize;
    var tallest = em;
    for (final leaf in node.children) {
      tallest = math.max(tallest, baseSize * TextSize.of(leaf.style.attributes[Attribute.size.key]?.value).scale);
    }
    return Container(
      alignment: AlignmentDirectional.topEnd,
      padding: EdgeInsetsDirectional.only(end: em * 0.45),
      child: Text.rich(
        TextSpan(
          children: [
            // Takes the item's line height without taking any width.
            if (tallest > em) TextSpan(text: '\u200B', style: TextStyle(fontSize: tallest)),
            marker,
          ],
        ),
        style: style.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
        maxLines: 1,
        softWrap: false,
      ),
    );
  }

  /// [style] with the variable font's weight and optical size axes set:
  /// Flutter does not map [FontWeight] or font size onto them by itself.
  static TextStyle? _withAxes(TextStyle? style, Map<String, Attribute<Object?>> attrs, TextStyle base) {
    final bold = attrs.containsKey(Attribute.bold.key);
    final size = TextSize.of(attrs[Attribute.size.key]?.value);
    if (!bold && size == TextSize.normal) return style;
    return (style ?? const TextStyle()).copyWith(
      fontVariations: [
        for (final v in base.fontVariations ?? const <FontVariation>[])
          if (v.axis != 'wght' && v.axis != 'opsz') v,
        FontVariation.weight(bold ? 700 : 400),
        FontVariation.opticalSize((base.fontSize! * size.scale).clamp(6, 144)),
      ],
    );
  }
}

enum _BulletShape { disc, circle, square }

/// A list bullet, drawn rather than typed so every depth looks the same in
/// any font. It stands on the baseline as tall as lowercase letters, so the
/// bullet is centred on them.
class _Bullet extends StatelessWidget {
  const _Bullet({required this.style, required this.shape});

  final TextStyle style;
  final _BulletShape shape;

  @override
  Widget build(BuildContext context) {
    final em = MediaQuery.textScalerOf(context).scale(style.fontSize ?? 16);
    return SizedBox(
      width: em * 0.4,
      height: em * 0.52,
      child: CustomPaint(
        painter: _BulletPainter(
          shape,
          style.color ?? DefaultTextStyle.of(context).style.color ?? Colors.black,
        ),
      ),
    );
  }
}

class _BulletPainter extends CustomPainter {
  _BulletPainter(this.shape, this.color);

  final _BulletShape shape;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final d = size.width * 0.8;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..isAntiAlias = true;
    switch (shape) {
      case _BulletShape.disc:
        canvas.drawCircle(center, d / 2, paint);
      case _BulletShape.circle:
        canvas.drawCircle(
          center,
          d / 2 - d * 0.09,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = d * 0.18,
        );
      case _BulletShape.square:
        canvas.drawRect(Rect.fromCenter(center: center, width: d * 0.9, height: d * 0.9), paint);
    }
  }

  @override
  bool shouldRepaint(_BulletPainter old) => old.shape != shape || old.color != color;
}
